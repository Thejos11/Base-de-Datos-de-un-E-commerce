-- 08_Auditoria_Verificacion.sql
-- Ejecutar después de 01..07 en una instancia MySQL 8.0+ limpia.

USE ecommerce;

-- 1. Conteo de objetos requeridos
SELECT 'FUNCIONES' AS objeto, COUNT(*) AS cantidad
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'ecommerce' AND ROUTINE_TYPE = 'FUNCTION'
UNION ALL
SELECT 'PROCEDIMIENTOS', COUNT(*)
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'ecommerce' AND ROUTINE_TYPE = 'PROCEDURE'
UNION ALL
SELECT 'TRIGGERS', COUNT(*)
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'ecommerce'
UNION ALL
SELECT 'EVENTOS', COUNT(*)
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'ecommerce';

-- 2. Funciones exigidas
SELECT ROUTINE_NAME
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'ecommerce'
  AND ROUTINE_TYPE = 'FUNCTION'
ORDER BY ROUTINE_NAME;

-- 3. Restricciones principales
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = 'ecommerce'
ORDER BY TABLE_NAME, CONSTRAINT_TYPE, CONSTRAINT_NAME;

-- 4. Eventos y estado
SELECT EVENT_NAME, STATUS, EVENT_DEFINITION
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = 'ecommerce'
ORDER BY EVENT_NAME;

-- 5. Integridad: productos con stock negativo
SELECT COUNT(*) AS productos_stock_negativo
FROM productos
WHERE stock < 0;

-- 6. Integridad: detalles con cantidades inválidas
SELECT COUNT(*) AS detalles_cantidad_invalida
FROM detalle_ventas
WHERE cantidad <= 0;

-- 7. Integridad: ventas sin detalle
SELECT COUNT(*) AS ventas_sin_detalle
FROM ventas v
LEFT JOIN detalle_ventas d ON d.id_venta = v.id_venta
WHERE d.id_detalle IS NULL;

-- 8. Integridad: ventas cuyo total no coincide con sus detalles
SELECT COUNT(*) AS ventas_total_inconsistente
FROM ventas v
JOIN (
    SELECT id_venta, COALESCE(SUM(subtotal),0) AS total_detalle
    FROM detalle_ventas
    GROUP BY id_venta
) d ON d.id_venta = v.id_venta
WHERE v.total <> d.total_detalle;

-- 9. Integridad: referidos inexistentes
SELECT COUNT(*) AS referencias_cliente_invalidas
FROM clientes c
LEFT JOIN clientes r ON r.id_cliente = c.id_referido_por
WHERE c.id_referido_por IS NOT NULL AND r.id_cliente IS NULL;

-- 10. Persistencia: filas de backup
SELECT
    (SELECT COUNT(*) FROM productos) AS productos,
    (SELECT COUNT(*) FROM backup_productos) AS backup_productos,
    (SELECT COUNT(*) FROM ventas) AS ventas,
    (SELECT COUNT(*) FROM backup_ventas) AS backup_ventas,
    (SELECT COUNT(*) FROM detalle_ventas) AS detalle_ventas,
    (SELECT COUNT(*) FROM backup_detalle_ventas) AS backup_detalle_ventas,
    (SELECT COUNT(*) FROM clientes) AS clientes,
    (SELECT COUNT(*) FROM backup_clientes) AS backup_clientes;

-- 11. Seguridad: usuarios del proyecto
SELECT User, Host
FROM mysql.user
WHERE User IN (
    'admin_user','marketing_user','inventory_user',
    'support_user','analyst_user','audit_user'
)
ORDER BY User, Host;

-- 12. Seguridad: asociación usuario-sucursal
SELECT * FROM usuario_sucursal ORDER BY usuario_host;

-- 13. Vistas de seguridad
SHOW FULL TABLES IN ecommerce WHERE Table_type = 'VIEW';

-- 14. Funciones de prueba
SELECT
    fn_ValidarFormatoEmail('prueba@correo.com') AS email_valido,
    fn_ValidarFormatoEmail('correo_invalido') AS email_invalido,
    fn_AplicarDescuento(100000, 10) AS descuento_10,
    fn_ValidarComplejidadContrasena('DemoSegura#2026') AS password_valida;

-- 15. Estado del scheduler
SHOW VARIABLES LIKE 'event_scheduler';

-- 16. Verificación del aislamiento por sucursal.
-- Ejecutar autenticado como un usuario que tenga registro en usuario_sucursal:
-- SELECT * FROM v_ventas_sucursal_usuario;
