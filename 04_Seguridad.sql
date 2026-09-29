-- =====================================================================
-- 04_Seguridad.sql - VERSION RECTIFICADA
-- Seguridad, roles, usuarios, privilegios y aislamiento por sucursal.
-- Requiere MySQL 8.0+ y ejecución administrativa.
-- =====================================================================
USE ecommerce;

CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
CREATE ROLE IF NOT EXISTS 'Visitante';

-- Administrador
GRANT ALL PRIVILEGES ON ecommerce.* TO 'Administrador_Sistema' WITH GRANT OPTION;

-- Marketing: solo lectura de datos comerciales y ejecución del reporte autorizado
GRANT SELECT ON ecommerce.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.clientes TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.productos TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.promociones TO 'Gerente_Marketing';

-- Analista: lectura de todas las tablas EXCEPTO las de auditoria
GRANT SELECT ON ecommerce.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce.detalle_ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce.proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce.sucursales TO 'Analista_Datos';
GRANT SELECT ON ecommerce.ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce.promociones TO 'Analista_Datos';
-- NOTA: No se conceden permisos en tablas de auditoria (log_*, solicitudes_permiso)

-- Inventario: puede consultar catálogo y modificar únicamente columnas autorizadas
GRANT SELECT ON ecommerce.productos TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce.categorias TO 'Empleado_Inventario';
GRANT SELECT ON ecommerce.proveedores TO 'Empleado_Inventario';
GRANT UPDATE (stock, ubicacion, descripcion, peso_kg) ON ecommerce.productos TO 'Empleado_Inventario';

-- Atención: acceso de lectura; las ventas se consultan mediante vista filtrada por sucursal
GRANT SELECT ON ecommerce.detalle_ventas TO 'Atencion_Cliente';

-- Auditor financiero
GRANT SELECT ON ecommerce.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce.log_cambios_precio TO 'Auditor_Financiero';

-- Visitante
GRANT SELECT ON ecommerce.productos TO 'Visitante';

-- Usuarios de demostración: las contraseñas se almacenan como credenciales del servidor.
-- Deben cambiarse inmediatamente en cualquier entorno real.
CREATE USER IF NOT EXISTS 'admin_user'@'localhost'     IDENTIFIED BY 'AdminSeguro#2026';
CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' IDENTIFIED BY 'Marketing#2026';
CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' IDENTIFIED BY 'Inventario#2026';
CREATE USER IF NOT EXISTS 'support_user'@'localhost'   IDENTIFIED BY 'Soporte#2026';
CREATE USER IF NOT EXISTS 'analyst_user'@'localhost'   IDENTIFIED BY 'Analista#2026';
CREATE USER IF NOT EXISTS 'audit_user'@'localhost'     IDENTIFIED BY 'Auditor#2026';

GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
GRANT 'Gerente_Marketing'     TO 'marketing_user'@'localhost';
GRANT 'Empleado_Inventario'   TO 'inventory_user'@'localhost';
GRANT 'Atencion_Cliente'      TO 'support_user'@'localhost';
GRANT 'Analista_Datos'        TO 'analyst_user'@'localhost';
GRANT 'Auditor_Financiero'    TO 'audit_user'@'localhost';

SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Gerente_Marketing'     TO 'marketing_user'@'localhost';
SET DEFAULT ROLE 'Empleado_Inventario'   TO 'inventory_user'@'localhost';
SET DEFAULT ROLE 'Atencion_Cliente'      TO 'support_user'@'localhost';
SET DEFAULT ROLE 'Analista_Datos'        TO 'analyst_user'@'localhost';
SET DEFAULT ROLE 'Auditor_Financiero'    TO 'audit_user'@'localhost';

-- Política de contraseñas del servidor (si el componente validate_password está instalado).
-- ALTER USER 'admin_user'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;

CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, ciudad, region, nivel_lealtad
FROM clientes;
GRANT SELECT ON ecommerce.v_info_clientes_basica TO 'Atencion_Cliente';

-- Asociación explícita usuario -> sucursal.
CREATE TABLE IF NOT EXISTS usuario_sucursal (
    usuario_host VARCHAR(200) PRIMARY KEY,
    id_sucursal INT NOT NULL,
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

INSERT INTO usuario_sucursal (usuario_host, id_sucursal) VALUES
('marketing_user@localhost', 1),
('inventory_user@localhost', 1),
('support_user@localhost', 1),
('analyst_user@localhost', 1),
('audit_user@localhost', 1)
ON DUPLICATE KEY UPDATE id_sucursal = VALUES(id_sucursal);

-- Vista de ventas filtrada automáticamente por la sucursal asociada al usuario.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_ventas_sucursal_usuario AS
SELECT v.*
FROM ventas v
JOIN usuario_sucursal us
  ON us.id_sucursal = v.id_sucursal
 AND us.usuario_host = USER();

GRANT SELECT ON ecommerce.v_ventas_sucursal_usuario TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce.v_ventas_sucursal_usuario TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce.v_ventas_sucursal_usuario TO 'Analista_Datos';
GRANT SELECT ON ecommerce.v_ventas_sucursal_usuario TO 'Auditor_Financiero';

-- Elimina el acceso directo a ventas para los roles que deben estar aislados por sucursal.
-- Solo se revoca para roles que tienen el permiso concedido explicitamente
REVOKE SELECT ON ecommerce.ventas FROM 'Gerente_Marketing';
REVOKE SELECT ON ecommerce.ventas FROM 'Analista_Datos';

-- Reporte autorizado para Marketing.
-- NOTA: El procedimiento sp_GenerarReporteMensualVentas se crea en 07_Procedimientos_Almacenados.sql
-- Ejecutar ese archivo ANTES de este grant, o mover este grant al final de 07_Procedimientos_Almacenados.sql
-- GRANT EXECUTE ON PROCEDURE ecommerce.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

-- Límite de consultas por hora para Analista_Datos.
ALTER USER 'analyst_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 500;

-- Tabla para integración de auditoría de autenticación.
-- MySQL Community no expone por defecto todos los fallos de autenticación
-- como filas SQL; el llenado automático requiere auditoría del servidor.
CREATE TABLE IF NOT EXISTS log_intentos_login (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    usuario       VARCHAR(100) NOT NULL,
    host_origen   VARCHAR(150) NULL,
    fecha_intento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    exitoso       BOOLEAN NOT NULL
) ENGINE=InnoDB;

-- Procedimiento de registro para la capa de aplicacion.
DROP PROCEDURE IF EXISTS sp_RegistrarIntentoLogin;
CREATE PROCEDURE sp_RegistrarIntentoLogin(
    IN p_usuario VARCHAR(100),
    IN p_host VARCHAR(150),
    IN p_exitoso BOOLEAN
)
BEGIN
    INSERT INTO log_intentos_login(usuario, host_origen, exitoso)
    VALUES (p_usuario, p_host, p_exitoso);
END;

-- Root remoto:
-- No se elimina mysql.user desde el proyecto. Verificar y corregir las cuentas
-- administrativas del servidor con:
-- SELECT User, Host FROM mysql.user WHERE User = 'root';
-- La restricción definitiva es una configuración del servidor MySQL.
