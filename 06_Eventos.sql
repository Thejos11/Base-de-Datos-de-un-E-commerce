-- =====================================================================
-- 06_Eventos.sql
-- Tabla de reportes semanales + 20 eventos programados de mantenimiento
-- y automatización de negocio.
-- Motor objetivo: MySQL 8.0+
-- Ejecutar con:  mysql -u root -p ecommerce < 06_Eventos.sql
-- =====================================================================

USE ecommerce;

-- Tabla para reporte de ventas semanales
CREATE TABLE IF NOT EXISTS reporte_ventas_semanales (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio   DATE NOT NULL,
    semana_fin      DATE NOT NULL,
    num_ventas      INT NOT NULL,
    total_vendido   DECIMAL(14,2) NOT NULL,
    fecha_generado  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tablas de apoyo usadas por los eventos
CREATE TABLE IF NOT EXISTS reorden_productos (
    id_reorden   INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    stock_minimo INT NOT NULL,
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ranking_productos (
    id_producto        INT PRIMARY KEY,
    unidades_30d       INT NOT NULL DEFAULT 0,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    fecha         DATE PRIMARY KEY,
    num_ventas    INT NOT NULL,
    total_vendido DECIMAL(14,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS inconsistencias_datos (
    id_inconsistencia INT AUTO_INCREMENT PRIMARY KEY,
    descripcion  VARCHAR(255) NOT NULL,
    id_referencia INT NULL,
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS cupones_cumpleanos (
    id_cupon    INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    codigo      VARCHAR(30) NOT NULL,
    fecha       DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    anio_mes       VARCHAR(7) PRIMARY KEY,
    num_ventas     INT NOT NULL,
    total_vendido  DECIMAL(14,2) NOT NULL,
    nuevos_clientes INT NOT NULL,
    ticket_promedio DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS log_tamano_bd (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb   DECIMAL(12,2) NOT NULL,
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_alerta   INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    motivo      VARCHAR(255) NOT NULL,
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS reporte_proveedores_mensual (
    id_reporte    INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor  INT NOT NULL,
    anio_mes      VARCHAR(7) NOT NULL,
    unidades_vendidas INT NOT NULL,
    ingresos_generados DECIMAL(14,2) NOT NULL,
    FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS log_cambios_precio_historico LIKE log_cambios_precio;
CREATE TABLE IF NOT EXISTS log_cambio_estado_pedido_historico LIKE log_cambio_estado_pedido;

-- Activar el planificador de eventos
SET GLOBAL event_scheduler = ON;

-- 1. Genera un reporte de ventas semanal
DROP EVENT IF EXISTS evt_generate_weekly_sales_report;
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO reporte_ventas_semanales (semana_inicio, semana_fin, num_ventas, total_vendido)
    SELECT DATE_SUB(CURDATE(), INTERVAL 7 DAY), CURDATE(), COUNT(*), COALESCE(SUM(total),0)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND estado <> 'Cancelado';
END;

-- 2. Borra carritos huérfanos de más de 90 días
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily;
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    DELETE FROM carrito_items WHERE fecha_agregado < DATE_SUB(NOW(), INTERVAL 90 DAY);
END;

-- 3. Archiva logs de más de 6 meses
DROP EVENT IF EXISTS evt_archive_old_logs_monthly;
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO log_cambios_precio_historico
    SELECT * FROM log_cambios_precio
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    INSERT INTO log_cambio_estado_pedido_historico
    SELECT * FROM log_cambio_estado_pedido
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM log_cambios_precio
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM log_cambio_estado_pedido
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END;

-- 4. Desactiva promociones expiradas
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly;
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE promociones SET activa = FALSE WHERE fecha_fin < CURDATE() AND activa = TRUE;
END;

-- 5. Recalcula el nivel de lealtad de los clientes cada noche
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly;
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '02:00:00'))
DO
BEGIN
    UPDATE clientes SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente);
END;

-- 6. Crea una lista de productos que necesitan reabastecimiento
DROP EVENT IF EXISTS evt_generate_reorder_list_daily;
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO reorden_productos (id_producto, stock_actual, stock_minimo)
    SELECT id_producto, stock, stock_minimo FROM productos
    WHERE stock < stock_minimo AND activo = TRUE;
END;

-- 7. Reconstruye los índices de las tablas más usadas
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly;
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    ALTER TABLE productos ENGINE=InnoDB;
    ALTER TABLE ventas ENGINE=InnoDB;
    ALTER TABLE detalle_ventas ENGINE=InnoDB;
END;

-- 8. Desactiva cuentas de clientes sin actividad hace más de un año
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly;
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    UPDATE clientes SET activo = FALSE
    WHERE (fecha_ultimo_pedido IS NULL OR fecha_ultimo_pedido < DATE_SUB(NOW(), INTERVAL 1 YEAR))
      AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR);
END;

-- 9. Agrega los datos de ventas del día en una tabla de resumen
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data;
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO resumen_ventas_diarias (fecha, num_ventas, total_vendido)
    SELECT CURDATE() - INTERVAL 1 DAY, COUNT(*), COALESCE(SUM(total),0)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() - INTERVAL 1 DAY AND estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE num_ventas = VALUES(num_ventas), total_vendido = VALUES(total_vendido);
END;

-- 10. Busca inconsistencias en los datos (ventas sin detalles)
DROP EVENT IF EXISTS evt_check_data_consistency_nightly;
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '03:00:00'))
DO
BEGIN
    INSERT INTO inconsistencias_datos (descripcion, id_referencia)
    SELECT 'Venta sin líneas de detalle', v.id_venta
    FROM ventas v LEFT JOIN detalle_ventas dv ON dv.id_venta = v.id_venta
    WHERE dv.id_detalle IS NULL;
END;

-- 11. Genera cupones para clientes que cumplen años
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily;
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO cupones_cumpleanos (id_cliente, codigo)
    SELECT id_cliente, CONCAT('CUMPLE-', id_cliente, '-', YEAR(CURDATE()))
    FROM clientes
    WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE()) AND DAY(fecha_nacimiento) = DAY(CURDATE());
END;

-- 12. Actualiza el ranking de los productos más populares
DROP EVENT IF EXISTS evt_update_product_rankings_hourly;
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    REPLACE INTO ranking_productos (id_producto, unidades_30d)
    SELECT id_producto, SUM(cantidad)
    FROM detalle_ventas
    WHERE fecha_venta >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY id_producto;
END;

-- 13. Realiza un backup lógico de las tablas más importantes cada noche
DROP EVENT IF EXISTS evt_backup_critical_tables_daily;
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '01:00:00'))
DO
BEGIN
    TRUNCATE backup_productos;
    INSERT INTO backup_productos SELECT * FROM productos;
    TRUNCATE backup_ventas;
    INSERT INTO backup_ventas SELECT * FROM ventas;
    TRUNCATE backup_detalle_ventas;
    INSERT INTO backup_detalle_ventas SELECT * FROM detalle_ventas;
    TRUNCATE backup_clientes;
    INSERT INTO backup_clientes SELECT * FROM clientes;
END;

-- 14. Vacía los carritos de compra abandonados hace más de 72 horas
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily;
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    DELETE FROM carrito_items WHERE fecha_agregado < DATE_SUB(NOW(), INTERVAL 72 HOUR);
END;

-- 15. Calcula los KPIs del mes
DROP EVENT IF EXISTS evt_calculate_monthly_kpis;
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO kpis_mensuales (anio_mes, num_ventas, total_vendido, nuevos_clientes, ticket_promedio)
    SELECT DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m'),
           COUNT(DISTINCT v.id_venta),
           COALESCE(SUM(v.total), 0),
           (SELECT COUNT(*) FROM clientes WHERE DATE_FORMAT(fecha_registro,'%Y-%m') = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m')),
           COALESCE(AVG(v.total), 0)
    FROM ventas v
    WHERE DATE_FORMAT(v.fecha_venta, '%Y-%m') = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m')
      AND v.estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE num_ventas = VALUES(num_ventas), total_vendido = VALUES(total_vendido),
                            nuevos_clientes = VALUES(nuevos_clientes), ticket_promedio = VALUES(ticket_promedio);
END;

-- 16. Actualiza las vistas materializadas
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly;
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '04:00:00'))
DO
BEGIN
    DELETE FROM resumen_ventas_diarias WHERE fecha = CURDATE();
    INSERT INTO resumen_ventas_diarias (fecha, num_ventas, total_vendido)
    SELECT CURDATE(),
           COUNT(DISTINCT dv.id_venta),
           COALESCE(SUM(dv.subtotal),0)
    FROM detalle_ventas dv
    JOIN ventas v ON v.id_venta = dv.id_venta
    WHERE DATE(dv.fecha_venta) = CURDATE()
      AND v.estado <> 'Cancelado';
END;

-- 17. Registra el tamaño de la base de datos
DROP EVENT IF EXISTS evt_log_database_size_weekly;
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO log_tamano_bd (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables WHERE table_schema = 'ecommerce';
END;

-- 18. Busca patrones de actividad sospechosa
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly;
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    INSERT INTO alertas_fraude (id_cliente, motivo)
    SELECT id_cliente, CONCAT('Más de 3 pedidos cancelados en las últimas 24 horas (', COUNT(*), ')')
    FROM ventas
    WHERE estado = 'Cancelado' AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY id_cliente
    HAVING COUNT(*) > 3;
END;

-- 19. Crea un reporte mensual sobre el rendimiento de los proveedores
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly;
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    INSERT INTO reporte_proveedores_mensual (id_proveedor, anio_mes, unidades_vendidas, ingresos_generados)
    SELECT p.id_proveedor, DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m'),
           COALESCE(SUM(dv.cantidad),0), COALESCE(SUM(dv.subtotal),0)
    FROM proveedores p
    LEFT JOIN productos pr ON pr.id_proveedor = p.id_proveedor
    LEFT JOIN detalle_ventas dv ON dv.id_producto = pr.id_producto
        AND DATE_FORMAT(dv.fecha_venta,'%Y-%m') = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m')
    GROUP BY p.id_proveedor;
END;

-- 20. Elimina permanentemente registros marcados para borrado
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly;
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK STARTS (CURRENT_DATE + INTERVAL 1 DAY)
DO
BEGIN
    -- Solo elimina físicamente registros que no tienen dependencias históricas.
    DELETE FROM productos
    WHERE eliminado_en IS NOT NULL
      AND eliminado_en < DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND NOT EXISTS (SELECT 1 FROM detalle_ventas dv WHERE dv.id_producto = productos.id_producto)
      AND NOT EXISTS (SELECT 1 FROM promociones pr WHERE pr.id_producto = productos.id_producto);

    DELETE FROM clientes
    WHERE eliminado_en IS NOT NULL
      AND eliminado_en < DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND NOT EXISTS (SELECT 1 FROM ventas v WHERE v.id_cliente = clientes.id_cliente)
      AND NOT EXISTS (SELECT 1 FROM resenas r WHERE r.id_cliente = clientes.id_cliente)
      AND NOT EXISTS (SELECT 1 FROM carrito_items ci WHERE ci.id_cliente = clientes.id_cliente)
      AND NOT EXISTS (SELECT 1 FROM creditos_cliente cc WHERE cc.id_cliente = clientes.id_cliente);
END;

