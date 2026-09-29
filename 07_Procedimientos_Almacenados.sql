-- =====================================================================
-- 07_Procedimientos_Almacenados.sql
-- 20 procedimientos almacenados para operaciones complejas y transaccionales.
-- Motor objetivo: MySQL 8.0+
-- Ejecutar con:  mysql -u root -p ecommerce < 07_Procedimientos_Almacenados.sql
-- =====================================================================

USE ecommerce;

-- 1. Procesa una nueva venta de forma transaccional
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta;
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    IN p_productos JSON
)
BEGIN
    DECLARE v_id_venta INT;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_total_items INT;
    DECLARE v_id_producto INT;
    DECLARE v_cantidad INT;
    DECLARE v_precio DECIMAL(12,2);
    DECLARE v_stock INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_productos IS NULL OR JSON_TYPE(p_productos) <> 'ARRAY' OR JSON_LENGTH(p_productos) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Debe proporcionar al menos un producto válido.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente AND activo = TRUE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente no existe o está inactivo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sucursales WHERE id_sucursal = p_id_sucursal) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La sucursal no existe.';
    END IF;

    SET v_total_items = JSON_LENGTH(p_productos);

    START TRANSACTION;
        INSERT INTO ventas (id_cliente, id_sucursal, estado, total)
        VALUES (p_id_cliente, p_id_sucursal, 'Pendiente de Pago', 0);
        SET v_id_venta = LAST_INSERT_ID();

        WHILE v_i < v_total_items DO
            SET v_id_producto = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_productos, CONCAT('$[', v_i, '].id_producto'))) AS UNSIGNED);
            SET v_cantidad = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_productos, CONCAT('$[', v_i, '].cantidad'))) AS UNSIGNED);

            IF v_id_producto IS NULL OR v_cantidad IS NULL OR v_cantidad <= 0 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Producto o cantidad inválidos en la venta.';
            END IF;

            SELECT stock, precio INTO v_stock, v_precio
            FROM productos
            WHERE id_producto = v_id_producto AND activo = TRUE
            FOR UPDATE;

            IF v_precio IS NULL OR v_stock < v_cantidad THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Producto inexistente, inactivo o sin stock suficiente.';
            END IF;

            INSERT INTO detalle_ventas
                (id_venta, id_producto, cantidad, precio_unitario_congelado, fecha_venta)
            VALUES
                (v_id_venta, v_id_producto, v_cantidad, v_precio, NOW());

            SET v_i = v_i + 1;
        END WHILE;

        UPDATE ventas
        SET total = fn_CalcularTotalVenta(v_id_venta),
            direccion_envio = (SELECT direccion_envio FROM clientes WHERE id_cliente = p_id_cliente)
        WHERE id_venta = v_id_venta;
    COMMIT;

    SELECT v_id_venta AS id_venta_generada;
END;

-- 2. Inserta un nuevo producto
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto;
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(120), IN p_descripcion TEXT, IN p_precio DECIMAL(12,2),
    IN p_costo DECIMAL(12,2), IN p_stock_inicial INT, IN p_id_categoria INT,
    IN p_id_proveedor INT, IN p_peso_kg DECIMAL(8,2)
)
BEGIN
    DECLARE v_sku VARCHAR(40);
    SET v_sku = fn_GenerarSKU(p_nombre, p_id_categoria);
    INSERT INTO productos (nombre, descripcion, precio, costo, stock, sku, id_categoria, id_proveedor, peso_kg)
    VALUES (p_nombre, p_descripcion, p_precio, p_costo, p_stock_inicial, v_sku, p_id_categoria, p_id_proveedor, p_peso_kg);
    SELECT LAST_INSERT_ID() AS id_producto_creado, v_sku AS sku_generado;
END;

-- 3. Actualiza la dirección de un cliente
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente;
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT, IN p_nueva_direccion VARCHAR(200), IN p_ciudad VARCHAR(60), IN p_region VARCHAR(60)
)
BEGIN
    UPDATE clientes
    SET direccion_envio = p_nueva_direccion, ciudad = p_ciudad, region = p_region
    WHERE id_cliente = p_id_cliente;

    UPDATE ventas
    SET direccion_envio = p_nueva_direccion
    WHERE id_cliente = p_id_cliente AND estado IN ('Pendiente de Pago', 'Procesando');
END;

-- 4. Gestiona devoluciones
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion;
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_detalle INT, IN p_cantidad INT, IN p_motivo VARCHAR(200)
)
BEGIN
    DECLARE v_id_producto INT;
    DECLARE v_id_cliente INT;
    DECLARE v_precio DECIMAL(12,2);
    DECLARE v_cantidad_comprada INT;
    DECLARE v_cantidad_devuelta INT DEFAULT 0;
    DECLARE v_monto DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_cantidad IS NULL OR p_cantidad <= 0 OR p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cantidad y motivo de devolución son obligatorios.';
    END IF;

    START TRANSACTION;
        SELECT dv.id_producto, v.id_cliente, dv.precio_unitario_congelado, dv.cantidad
          INTO v_id_producto, v_id_cliente, v_precio, v_cantidad_comprada
        FROM detalle_ventas dv
        JOIN ventas v ON v.id_venta = dv.id_venta
        WHERE dv.id_detalle = p_id_detalle
        FOR UPDATE;

        IF v_id_producto IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El detalle de venta no existe.';
        END IF;

        SELECT COALESCE(SUM(cantidad),0) INTO v_cantidad_devuelta
        FROM devoluciones
        WHERE id_detalle = p_id_detalle;

        IF p_cantidad > (v_cantidad_comprada - v_cantidad_devuelta) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad devuelta supera la cantidad comprada disponible.';
        END IF;

        SET v_monto = v_precio * p_cantidad;

        INSERT INTO devoluciones (id_detalle, cantidad, monto, motivo)
        VALUES (p_id_detalle, p_cantidad, v_monto, p_motivo);

        UPDATE productos SET stock = stock + p_cantidad WHERE id_producto = v_id_producto;

        INSERT INTO creditos_cliente (id_cliente, monto, motivo)
        VALUES (v_id_cliente, v_monto, CONCAT('Devolución: ', p_motivo));
    COMMIT;
END;

-- 5. Historial de compras de un cliente
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente;
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT v.id_venta, v.fecha_venta, v.estado, v.total, p.nombre AS producto,
           dv.cantidad, dv.precio_unitario_congelado
    FROM ventas v
    JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;
END;

-- 6. Ajustar stock manualmente
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock;
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT, IN p_stock_nuevo INT, IN p_motivo VARCHAR(200), IN p_usuario VARCHAR(100)
)
BEGIN
    DECLARE v_stock_anterior INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_stock_nuevo IS NULL OR p_stock_nuevo < 0 OR p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock, motivo y producto deben ser válidos.';
    END IF;

    START TRANSACTION;
        SELECT stock INTO v_stock_anterior FROM productos WHERE id_producto = p_id_producto FOR UPDATE;
        IF v_stock_anterior IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe.';
        END IF;

        UPDATE productos SET stock = p_stock_nuevo WHERE id_producto = p_id_producto;

        INSERT INTO ajustes_stock (id_producto, stock_anterior, stock_nuevo, motivo, usuario)
        VALUES (p_id_producto, v_stock_anterior, p_stock_nuevo, p_motivo, COALESCE(p_usuario, CURRENT_USER()));
    COMMIT;
END;

-- 7. Eliminar cliente de forma segura (anonimizar)
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura;
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
    SET nombre = 'Cliente', apellido = 'Eliminado',
        email = CONCAT('eliminado_', p_id_cliente, '@anonimo.local'),
        contrasena = SHA2(CONCAT('eliminado', p_id_cliente, NOW()), 256),
        direccion_envio = NULL, ciudad = NULL, region = NULL,
        activo = FALSE, eliminado_en = NOW()
    WHERE id_cliente = p_id_cliente;
END;

-- 8. Aplicar descuento por categoría
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria;
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(IN p_id_categoria INT, IN p_porcentaje DECIMAL(5,2))
BEGIN
    UPDATE productos
    SET precio = fn_AplicarDescuento(precio, p_porcentaje)
    WHERE id_categoria = p_id_categoria;
END;

-- 9. Generar reporte mensual
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas;
CREATE PROCEDURE sp_GenerarReporteMensualVentas(IN p_anio INT, IN p_mes INT)
BEGIN
    SELECT COUNT(DISTINCT v.id_venta) AS num_ventas,
           COALESCE(SUM(v.total), 0) AS total_vendido,
           COALESCE(AVG(v.total), 0) AS ticket_promedio,
           COUNT(DISTINCT v.id_cliente) AS clientes_distintos
    FROM ventas v
    WHERE YEAR(v.fecha_venta) = p_anio AND MONTH(v.fecha_venta) = p_mes AND v.estado <> 'Cancelado';

    SELECT p.nombre, SUM(dv.cantidad) AS unidades, SUM(dv.subtotal) AS ingresos
    FROM detalle_ventas dv
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE YEAR(dv.fecha_venta) = p_anio AND MONTH(dv.fecha_venta) = p_mes
    GROUP BY p.nombre
    ORDER BY ingresos DESC;
END;

-- Conceder permiso de ejecucion al rol Gerente_Marketing
GRANT EXECUTE ON PROCEDURE ecommerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

-- 10. Cambiar estado de pedido
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido;
CREATE PROCEDURE sp_CambiarEstadoPedido(IN p_id_venta INT, IN p_nuevo_estado VARCHAR(30))
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    IF p_nuevo_estado NOT IN ('Pendiente de Pago','Pagado','Procesando','Enviado','Entregado','Cancelado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estado de pedido no permitido.';
    END IF;

    SELECT COUNT(*) INTO v_existe FROM ventas WHERE id_venta = p_id_venta;
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta no existe.';
    END IF;

    UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;

    INSERT INTO cola_notificaciones (evento, id_venta, payload)
    VALUES ('cambio_estado_pedido', p_id_venta,
            JSON_OBJECT('id_venta', p_id_venta, 'nuevo_estado', p_nuevo_estado));
END;

-- 11. Registrar nuevo cliente
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente;
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(60), IN p_apellido VARCHAR(60), IN p_email VARCHAR(120),
    IN p_contrasena_hash VARCHAR(255), IN p_direccion VARCHAR(200)
)
BEGIN
    IF EXISTS (SELECT 1 FROM clientes WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un cliente registrado con este correo electrónico.';
    END IF;
    IF NOT fn_ValidarFormatoEmail(p_email) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido.';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio)
    VALUES (p_nombre, p_apellido, p_email, p_contrasena_hash, p_direccion);

    SELECT LAST_INSERT_ID() AS id_cliente_creado;
END;

-- 12. Obtener detalles completos de un producto
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto;
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT p.*, c.nombre AS categoria, pr.nombre AS proveedor, pr.email_contacto AS proveedor_email
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    LEFT JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
    WHERE p.id_producto = p_id_producto;
END;

-- 13. Fusionar cuentas de cliente
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente;
CREATE PROCEDURE sp_FusionarCuentasCliente(IN p_id_cliente_principal INT, IN p_id_cliente_duplicado INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_cliente_principal IS NULL OR p_id_cliente_duplicado IS NULL
       OR p_id_cliente_principal = p_id_cliente_duplicado THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las cuentas a fusionar deben ser distintas y válidas.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente_principal)
       OR NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente_duplicado) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Una de las cuentas no existe.';
    END IF;

    START TRANSACTION;
        UPDATE ventas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
        UPDATE resenas SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;
        UPDATE carrito_items SET id_cliente = p_id_cliente_principal WHERE id_cliente = p_id_cliente_duplicado;

        UPDATE clientes c1
        JOIN clientes c2 ON c2.id_cliente = p_id_cliente_duplicado
        SET c1.total_gastado = c1.total_gastado + c2.total_gastado
        WHERE c1.id_cliente = p_id_cliente_principal;

        CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_duplicado);
    COMMIT;
END;

-- 14. Asignar proveedor a producto
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor;
CREATE PROCEDURE sp_AsignarProductoAProveedor(IN p_id_producto INT, IN p_id_proveedor INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM productos WHERE id_producto = p_id_producto) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM proveedores WHERE id_proveedor = p_id_proveedor) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor no existe.';
    END IF;
    UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
END;

-- 15. Búsqueda avanzada de productos
DROP PROCEDURE IF EXISTS sp_BuscarProductos;
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre VARCHAR(120), IN p_id_categoria INT, IN p_precio_min DECIMAL(12,2), IN p_precio_max DECIMAL(12,2)
)
BEGIN
    SELECT p.id_producto, p.nombre, p.precio, p.stock, c.nombre AS categoria
    FROM productos p
    LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE p.activo = TRUE
      AND (p_nombre IS NULL OR p.nombre LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min IS NULL OR p.precio >= p_precio_min)
      AND (p_precio_max IS NULL OR p.precio <= p_precio_max)
    ORDER BY p.nombre;
END;

-- 16. Dashboard de administración
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin;
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        (SELECT COUNT(*) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COALESCE(SUM(total),0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ingresos_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM productos WHERE stock < stock_minimo AND activo = TRUE) AS productos_bajo_stock,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Procesando') AS pedidos_en_proceso;
END;

-- 17. Procesar pago
DROP PROCEDURE IF EXISTS sp_ProcesarPago;
CREATE PROCEDURE sp_ProcesarPago(IN p_id_venta INT, IN p_metodo VARCHAR(30))
BEGIN
    DECLARE v_total DECIMAL(14,2);
    DECLARE v_estado VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_metodo IS NULL OR TRIM(p_metodo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El método de pago es obligatorio.';
    END IF;

    START TRANSACTION;
        SELECT estado INTO v_estado
        FROM ventas
        WHERE id_venta = p_id_venta
        FOR UPDATE;

        IF v_estado IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta no existe.';
        END IF;
        IF v_estado = 'Cancelado' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede pagar una venta cancelada.';
        END IF;
        IF EXISTS (SELECT 1 FROM pagos WHERE id_venta = p_id_venta AND estado = 'Aprobado') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La venta ya tiene un pago aprobado.';
        END IF;

        SET v_total = fn_CalcularTotalVenta(p_id_venta);

        INSERT INTO pagos (id_venta, metodo, monto, estado)
        VALUES (p_id_venta, p_metodo, v_total, 'Aprobado');

        UPDATE ventas
        SET estado = 'Pagado', total = v_total
        WHERE id_venta = p_id_venta;
    COMMIT;
END;

-- 18. Añadir reseña a producto
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto;
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN p_id_producto INT, IN p_id_cliente INT, IN p_calificacion TINYINT, IN p_comentario TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM detalle_ventas dv JOIN ventas v ON v.id_venta = dv.id_venta
        WHERE dv.id_producto = p_id_producto AND v.id_cliente = p_id_cliente AND v.estado <> 'Cancelado'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente debe haber comprado el producto para poder reseñarlo.';
    END IF;

    INSERT INTO resenas (id_producto, id_cliente, calificacion, comentario)
    VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario)
    ON DUPLICATE KEY UPDATE calificacion = p_calificacion, comentario = p_comentario, fecha = NOW();
END;

-- 19. Obtener productos relacionados
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados;
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT p2.id_producto, p2.nombre, COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    JOIN detalle_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv2.id_producto <> p_id_producto
    JOIN productos p2 ON p2.id_producto = dv2.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY p2.id_producto, p2.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END;

-- 20. Mover productos entre categorías
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias;
CREATE PROCEDURE sp_MoverProductosEntreCategorias(IN p_id_categoria_origen INT, IN p_id_categoria_destino INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_id_categoria_origen = p_id_categoria_destino THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las categorías de origen y destino deben ser distintas.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_origen)
       OR NOT EXISTS (SELECT 1 FROM categorias WHERE id_categoria = p_id_categoria_destino) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La categoría de origen o destino no existe.';
    END IF;

    START TRANSACTION;
        UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE id_categoria = p_id_categoria_origen;
    COMMIT;
END;

