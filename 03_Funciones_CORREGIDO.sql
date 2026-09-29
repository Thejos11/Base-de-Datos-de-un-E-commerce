-- =====================================================================
-- 03_Funciones_CORREGIDO.sql - VERSION SIN DELIMITER
-- Para phpMyAdmin y cualquier cliente MySQL
-- =====================================================================
USE ecommerce;

DROP FUNCTION IF EXISTS fn_CalcularTotalVenta;
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock;
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto;
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente;
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto;
DROP FUNCTION IF EXISTS fn_EsClienteNuevo;
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio;
DROP FUNCTION IF EXISTS fn_AplicarDescuento;
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra;
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail;
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria;
DROP FUNCTION IF EXISTS fn_ContarVentasCliente;
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra;
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad;
DROP FUNCTION IF EXISTS fn_GenerarSKU;
DROP FUNCTION IF EXISTS fn_CalcularIVA;
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria;
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega;
DROP FUNCTION IF EXISTS fn_ConvertirMoneda;
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena;

CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(14,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((
        SELECT SUM(subtotal) FROM detalle_ventas WHERE id_venta = p_id_venta
    ), 0);
END;

CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_stock INT DEFAULT 0;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN RETURN FALSE; END IF;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    RETURN COALESCE(v_stock, 0) >= p_cantidad;
END;

CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN (SELECT precio FROM productos WHERE id_producto = p_id_producto);
END;

CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((
        SELECT TIMESTAMPDIFF(YEAR, fecha_nacimiento, CURDATE())
        FROM clientes WHERE id_cliente = p_id_cliente
    ), 0);
END;

CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(205)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((
        SELECT CONCAT(
            UPPER(LEFT(TRIM(nombre),1)), LOWER(SUBSTRING(TRIM(nombre),2)), ' ',
            UPPER(LEFT(TRIM(apellido),1)), LOWER(SUBSTRING(TRIM(apellido),2))
        )
        FROM clientes WHERE id_cliente = p_id_cliente
    ), '');
END;

CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente AND estado NOT IN ('Cancelado','Pendiente de Pago');
    RETURN v_primera_compra IS NOT NULL
       AND v_primera_compra >= DATE_SUB(NOW(), INTERVAL 30 DAY);
END;

CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(14,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(14,2) DEFAULT 0;
    SELECT COALESCE(SUM(p.peso_kg * dv.cantidad),0)
      INTO v_peso_total
    FROM detalle_ventas dv
    JOIN productos p ON p.id_producto = dv.id_producto
    WHERE dv.id_venta = p_id_venta;
    RETURN ROUND(5.00 + (v_peso_total * 2.00), 2);
END;

CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(14,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
BEGIN
    IF p_monto IS NULL OR p_porcentaje IS NULL OR p_monto < 0
       OR p_porcentaje < 0 OR p_porcentaje > 100 THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END;

CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN (
        SELECT MAX(fecha_venta) FROM ventas
        WHERE id_cliente = p_id_cliente
          AND estado NOT IN ('Cancelado','Pendiente de Pago')
    );
END;

CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN p_email IS NOT NULL
       AND p_email REGEXP '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$';
END;

CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((
        SELECT c.nombre
        FROM productos p JOIN categorias c ON c.id_categoria = p.id_categoria
        WHERE p.id_producto = p_id_producto
    ), 'Sin Categor\'ia');
END;

CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((
        SELECT COUNT(*) FROM ventas
        WHERE id_cliente = p_id_cliente
          AND estado NOT IN ('Cancelado','Pendiente de Pago')
    ), 0);
END;

CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;
    SELECT MAX(fecha_venta) INTO v_ultima
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado','Pendiente de Pago');
    RETURN IF(v_ultima IS NULL, NULL, DATEDIFF(CURDATE(), v_ultima));
END;

CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(10)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2) DEFAULT 0;
    SELECT COALESCE(SUM(total),0) INTO v_total
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado','Pendiente de Pago');
    RETURN CASE
        WHEN v_total >= 5000 THEN 'Oro'
        WHEN v_total >= 1500 THEN 'Plata'
        ELSE 'Bronce'
    END;
END;

CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
DETERMINISTIC
BEGIN
    DECLARE v_base VARCHAR(20);
    SET v_base = UPPER(LEFT(REGEXP_REPLACE(COALESCE(p_nombre,''),'[^A-Za-z0-9]',''), 8));
    RETURN LEFT(CONCAT(
        'SKU-', LPAD(COALESCE(p_id_categoria,0),3,'0'), '-',
        COALESCE(v_base,'PRODUCTO'), '-',
        SUBSTRING(SHA2(CONCAT(COALESCE(p_nombre,''),'|',COALESCE(p_id_categoria,0)),256),1,10)
    ),50);
END;

CREATE FUNCTION fn_CalcularIVA(p_id_venta INT)
RETURNS DECIMAL(14,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN ROUND(fn_CalcularTotalVenta(p_id_venta) * 0.19, 2);
END;

CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN COALESCE((SELECT SUM(stock) FROM productos WHERE id_categoria = p_id_categoria),0);
END;

CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
NOT DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;
    RETURN DATE_ADD(CURDATE(), INTERVAL
        CASE
            WHEN v_ciudad IN ('Cu\'cuta','Bucaramanga') THEN 2
            WHEN v_ciudad IN ('Bogota\'','Medelli\'n','Cali') THEN 3
            ELSE 5
        END DAY);
END;

CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(14,2), p_moneda_destino VARCHAR(3))
RETURNS DECIMAL(14,2)
NOT DETERMINISTIC READS SQL DATA
BEGIN
    RETURN ROUND(
        p_monto * COALESCE(
            (SELECT tasa FROM tasas_cambio WHERE moneda = UPPER(p_moneda_destino)),
            1
        ), 2);
END;

CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN p_contrasena IS NOT NULL
       AND CHAR_LENGTH(p_contrasena) >= 8
       AND p_contrasena REGEXP '[A-Z]'
       AND p_contrasena REGEXP '[a-z]'
       AND p_contrasena REGEXP '[0-9]'
       AND p_contrasena REGEXP '[^A-Za-z0-9]';
END;
