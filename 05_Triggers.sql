-- =====================================================================
-- 05_Triggers.sql
-- Triggers que automatizan la lógica de negocio y protegen la integridad de los datos.
-- Motor objetivo: MySQL 8.0+
-- Ejecutar con:  mysql -u root -p ecommerce < 05_Triggers.sql
-- =====================================================================

USE ecommerce;

-- Tabla de auditoría de cambios de precio (usada por el trigger 1)
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_producto   INT NOT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL,
    usuario       VARCHAR(100) NOT NULL,
    fecha_cambio  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- Tablas de apoyo para los triggers de auditoría/alertas
CREATE TABLE IF NOT EXISTS log_nuevos_clientes (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    fecha_alta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS log_cambio_estado_pedido (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_venta      INT NOT NULL,
    estado_anterior VARCHAR(30) NOT NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha_cambio  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS log_permisos (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    detalle     VARCHAR(255) NOT NULL,
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atendida     BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_venta    INT NOT NULL,
    id_cliente  INT NOT NULL,
    fecha_venta DATETIME NOT NULL,
    estado      VARCHAR(30) NOT NULL,
    total       DECIMAL(14,2) NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_venta),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- 1. Guarda un log de cambios de precios
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update;
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <> OLD.precio THEN
        INSERT INTO log_cambios_precio (id_producto, precio_anterior, precio_nuevo, usuario)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio, CURRENT_USER());
    END IF;
END;

-- 2. Verifica el stock antes de registrar una línea de venta
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta;
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock IS NULL OR v_stock < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Stock insuficiente para registrar la venta de este producto.';
    END IF;
END;

-- 3. Decrementa el stock después de registrar una línea de venta
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta;
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos SET stock = stock - NEW.cantidad WHERE id_producto = NEW.id_producto;
END;

-- 4. Impide eliminar una categoría si tiene productos asociados
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products;
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_num_productos INT;
    SELECT COUNT(*) INTO v_num_productos FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_num_productos > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una categoría que tiene productos asociados.';
    END IF;
END;

-- 5. Registra en auditoría cada vez que se crea un nuevo cliente
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert;
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO log_nuevos_clientes (id_cliente) VALUES (NEW.id_cliente);
END;

-- 6. Actualiza total_gastado del cliente después de cada venta
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente;
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado NOT IN ('Cancelado', 'Pendiente de Pago') THEN
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END;

-- 7. Actualiza automáticamente la fecha de última modificación de un producto
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto;
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = CURRENT_TIMESTAMP;
END;

-- 8. Impide que el stock de un producto se actualice a un valor negativo
DROP TRIGGER IF EXISTS trg_prevent_negative_stock;
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El stock de un producto no puede ser negativo.';
    END IF;
END;

-- 9. Capitaliza la primera letra del nombre y apellido al insertar un cliente
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente;
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre   = CONCAT(UPPER(LEFT(NEW.nombre,1)), LOWER(SUBSTRING(NEW.nombre,2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido,1)), LOWER(SUBSTRING(NEW.apellido,2)));
END;

-- 10. Recalcula el total de la venta si se modifica un detalle_venta
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_insert;
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_insert
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(subtotal),0) FROM detalle_ventas WHERE id_venta = NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
END;

DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_update;
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_update
AFTER UPDATE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(subtotal),0) FROM detalle_ventas WHERE id_venta = NEW.id_venta)
    WHERE id_venta = NEW.id_venta;
    IF OLD.id_venta <> NEW.id_venta THEN
        UPDATE ventas
        SET total = (SELECT COALESCE(SUM(subtotal),0) FROM detalle_ventas WHERE id_venta = OLD.id_venta)
        WHERE id_venta = OLD.id_venta;
    END IF;
END;

DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_delete;
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_delete
AFTER DELETE ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (SELECT COALESCE(SUM(subtotal),0) FROM detalle_ventas WHERE id_venta = OLD.id_venta)
    WHERE id_venta = OLD.id_venta;
END;

-- 11. Audita cada cambio de estado en un pedido
DROP TRIGGER IF EXISTS trg_log_order_status_change;
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado <> OLD.estado THEN
        INSERT INTO log_cambio_estado_pedido (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END;

-- 12. Impide que el precio de un producto se establezca en cero o negativo
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less;
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El precio de un producto debe ser mayor que cero.';
    END IF;
END;

-- 13. Inserta una alerta si el stock baja del umbral mínimo
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock;
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < NEW.stock_minimo AND (OLD.stock >= OLD.stock_minimo OR OLD.stock <> NEW.stock) THEN
        INSERT INTO alertas_stock (id_producto, stock_actual) VALUES (NEW.id_producto, NEW.stock);
    END IF;
END;

-- 14. Mueve una venta eliminada a una tabla de archivo
DROP TRIGGER IF EXISTS trg_archive_deleted_venta;
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, estado, total)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.estado, OLD.total);
END;

-- 15. Valida el formato del email antes de insertar un cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer;
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electrónico del cliente no es válido.';
    END IF;
END;

-- 15b. Valida el formato del email antes de actualizar un cliente
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer_update;
CREATE TRIGGER trg_validate_email_format_on_customer_update
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NOT fn_ValidarFormatoEmail(NEW.email) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El formato del correo electrónico del cliente no es válido.';
    END IF;
END;

-- 16. Actualiza la fecha del último pedido en la tabla clientes
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer;
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado NOT IN ('Cancelado','Pendiente de Pago') THEN
        UPDATE clientes
        SET fecha_ultimo_pedido = GREATEST(COALESCE(fecha_ultimo_pedido, NEW.fecha_venta), NEW.fecha_venta)
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END;

-- Mantiene total_gastado y fecha_ultimo_pedido cuando cambia estado o total
DROP TRIGGER IF EXISTS trg_sync_customer_totals_after_venta_update;
CREATE TRIGGER trg_sync_customer_totals_after_venta_update
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado NOT IN ('Cancelado','Pendiente de Pago')
       AND NEW.estado IN ('Cancelado','Pendiente de Pago') THEN
        UPDATE clientes
        SET total_gastado = GREATEST(total_gastado - OLD.total, 0)
        WHERE id_cliente = OLD.id_cliente;
    ELSEIF OLD.estado IN ('Cancelado','Pendiente de Pago')
       AND NEW.estado NOT IN ('Cancelado','Pendiente de Pago') THEN
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total
        WHERE id_cliente = NEW.id_cliente;
    ELSEIF NEW.estado NOT IN ('Cancelado','Pendiente de Pago')
       AND (NEW.total <> OLD.total OR NEW.id_cliente <> OLD.id_cliente) THEN
        UPDATE clientes
        SET total_gastado = GREATEST(total_gastado - OLD.total, 0)
        WHERE id_cliente = OLD.id_cliente;
        UPDATE clientes
        SET total_gastado = total_gastado + NEW.total
        WHERE id_cliente = NEW.id_cliente;
    END IF;

    IF NEW.estado NOT IN ('Cancelado','Pendiente de Pago') THEN
        UPDATE clientes
        SET fecha_ultimo_pedido = GREATEST(COALESCE(fecha_ultimo_pedido, NEW.fecha_venta), NEW.fecha_venta)
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END;

-- 17. Impide que un cliente se referencie a sí mismo
DROP TRIGGER IF EXISTS trg_prevent_self_referral;
CREATE TRIGGER trg_prevent_self_referral
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NEW.id_referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END;

-- 17b. También validar al insertar
DROP TRIGGER IF EXISTS trg_prevent_self_referral_insert;
CREATE TRIGGER trg_prevent_self_referral_insert
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.id_referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo.';
    END IF;
END;

-- 18. Registra solicitudes de cambio de permisos (la auditoría de GRANT/REVOKE reales depende del servidor MySQL)
DROP TABLE IF EXISTS solicitudes_permiso;
CREATE TABLE solicitudes_permiso (
    id_solicitud INT AUTO_INCREMENT PRIMARY KEY,
    usuario_objetivo VARCHAR(100) NOT NULL,
    permiso VARCHAR(100) NOT NULL,
    accion ENUM('GRANT','REVOKE') NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

DROP TRIGGER IF EXISTS trg_log_permission_changes;
CREATE TRIGGER trg_log_permission_changes
AFTER INSERT ON solicitudes_permiso
FOR EACH ROW
BEGIN
    INSERT INTO log_permisos (detalle)
    VALUES (CONCAT(NEW.accion, ' "', NEW.permiso, '" para el usuario ', NEW.usuario_objetivo));
END;

-- 19. Asigna la categoría General si se inserta un producto sin categoría
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null;
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = (SELECT id_categoria FROM categorias WHERE nombre = 'General' LIMIT 1);
    END IF;
END;

-- 20. Mantiene el contador de productos por categoría
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria_insert;
CREATE TRIGGER trg_update_producto_count_in_categoria_insert
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
END;

DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria_delete;
CREATE TRIGGER trg_update_producto_count_in_categoria_delete
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
END;

DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria_update;
CREATE TRIGGER trg_update_producto_count_in_categoria_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NOT (OLD.id_categoria <=> NEW.id_categoria) THEN
        UPDATE categorias SET num_productos = num_productos - 1 WHERE id_categoria = OLD.id_categoria;
        UPDATE categorias SET num_productos = num_productos + 1 WHERE id_categoria = NEW.id_categoria;
    END IF;
END;

