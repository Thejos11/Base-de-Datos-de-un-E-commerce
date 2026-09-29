# 🛍️ Proyecto de Base de Datos MySQL — E-commerce

> **Versión rectificada:** 2.0 · **Motor:** MySQL 8.0+  
> Auditoría de seguridad, integridad, manejo de errores, persistencia y cumplimiento del enunciado.

## 🎯 Objetivo

Implementar una base de datos robusta para un E-commerce, con productos, categorías, proveedores, clientes, ventas, detalle de ventas, inventario, seguridad por roles, auditoría, funciones, triggers, eventos y procedimientos almacenados.

El proyecto fue revisado contra el documento original de requisitos y se corrigieron inconsistencias de estructura, dependencias, funciones incompletas, permisos, estados de pedidos, persistencia y manejo transaccional.

## 📁 Estructura

| Archivo | Contenido |
|---|---|
| `01_Esquema_y_Datos.sql` | Base de datos, tablas, claves, restricciones, datos y backups |
| `02_Consultas_Avanzadas.sql` | 20 consultas de análisis y reporteo |
| `03_Funciones.sql` | 20 funciones definidas por el usuario |
| `04_Seguridad.sql` | Roles, usuarios, privilegios y aislamiento por sucursal |
| `05_Triggers.sql` | Triggers de integridad, auditoría e inventario |
| `06_Eventos.sql` | 20 eventos programados de mantenimiento |
| `07_Procedimientos_Almacenados.sql` | 20 procedimientos almacenados |
| `08_Auditoria_Verificacion.sql` | Verificación automática de objetos, integridad, seguridad y persistencia |

## ▶️ Orden de ejecución

El orden corregido es importante porque existen dependencias entre funciones, triggers, procedimientos, roles y permisos:

```text
01_Esquema_y_Datos.sql
        ↓
03_Funciones.sql
        ↓
05_Triggers.sql
        ↓
07_Procedimientos_Almacenados.sql
        ↓
04_Seguridad.sql
        ↓
06_Eventos.sql
        ↓
02_Consultas_Avanzadas.sql
```

### Configuración del servidor

Como administrador:

```sql
SET GLOBAL log_bin_trust_function_creators = 1;
SET GLOBAL event_scheduler = ON;
```

Después:

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p ecommerce < 03_Funciones.sql
mysql -u root -p ecommerce < 05_Triggers.sql
mysql -u root -p ecommerce < 07_Procedimientos_Almacenados.sql
mysql -u root -p ecommerce < 04_Seguridad.sql
mysql -u root -p ecommerce < 06_Eventos.sql
mysql -u root -p ecommerce < 02_Consultas_Avanzadas.sql
# 8. Verificación final (opcional)
mysql -u root -p ecommerce < 08_Auditoria_Verificacion.sql
```

> `01_Esquema_y_Datos.sql` crea la base `ecommerce`, por eso no se debe indicar una base inexistente al ejecutar ese primer archivo.

## 🔐 Seguridad

Se implementan los roles:

- `Administrador_Sistema`
- `Gerente_Marketing`
- `Analista_Datos`
- `Empleado_Inventario`
- `Atencion_Cliente`
- `Auditor_Financiero`
- `Visitante`

### Controles aplicados

- Principio de mínimo privilegio.
- UPDATE por columnas para Inventario.
- Vista `v_info_clientes_basica` sin contraseña ni dirección.
- Aislamiento de ventas mediante `usuario_sucursal` y `v_ventas_sucursal_usuario`.
- Límite de 500 consultas/hora para `analyst_user`.
- Root remoto tratado como configuración del servidor, no mediante borrado directo de `mysql.user`.
- Tabla de auditoría de autenticación.
- Procedimiento `sp_RegistrarIntentoLogin` para registrar intentos desde la capa de aplicación.

### Importante sobre contraseñas

Las contraseñas de usuarios MySQL incluidas en `04_Seguridad.sql` son credenciales de demostración y deben cambiarse inmediatamente en un entorno real.

Las contraseñas de clientes de datos de ejemplo ya no están almacenadas como texto identificable: se cargan como hashes SHA-256 de demostración. Para una aplicación real se recomienda generar/verificar contraseñas con Argon2id o bcrypt en la capa de aplicación.

## 🧱 Integridad de datos

Se aplican:

- PRIMARY KEY.
- FOREIGN KEY.
- `ON DELETE` / `ON UPDATE` explícitos.
- `UNIQUE`.
- `CHECK`.
- `ENUM` para estados.
- `GENERATED ALWAYS` para subtotales.
- FK de ventas a sucursales.
- FK de referidos entre clientes.
- Restricción única `(id_venta, id_producto)`.
- Validaciones de email, stock, precio, cantidad y categorías.
- Protección contra devoluciones superiores a la cantidad comprada.

## 💾 Persistencia y recuperación

Se incorporan tablas de backup para:

- `productos`
- `ventas`
- `detalle_ventas`
- `clientes`

El evento diario de backup copia su contenido a las tablas de respaldo.

Además:

- Los logs antiguos se trasladan a tablas históricas antes de eliminarse.
- Las ventas eliminadas se archivan mediante trigger.
- Los clientes se anonimizan mediante procedimiento.
- El borrado físico de registros soft-delete comprueba dependencias antes de eliminar.

> El backup SQL interno **no sustituye** un backup externo (`mysqldump`, snapshots, réplica, etc.).

## ⚠️ Manejo de errores

Los procedimientos transaccionales incluyen:

```sql
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    ROLLBACK;
    RESIGNAL;
END;
```

Esto garantiza rollback ante errores y devuelve el error a la capa que llamó al procedimiento.

También se validan:

- Cliente y sucursal existentes.
- Productos activos.
- Stock disponible.
- JSON de productos.
- Estados válidos.
- Pagos duplicados.
- Devoluciones excesivas.
- Categorías y proveedores inexistentes.
- Parámetros inválidos.

## 🧮 Funciones

`03_Funciones.sql` contiene las **20 funciones exigidas**, incluyendo:

- `fn_CalcularTotalVenta`
- `fn_VerificarDisponibilidadStock`
- `fn_ObtenerPrecioProducto`
- `fn_CalcularEdadCliente`
- `fn_FormatearNombreCompleto`
- `fn_EsClienteNuevo`
- `fn_CalcularCostoEnvio`
- `fn_AplicarDescuento`
- `fn_ObtenerUltimaFechaCompra`
- `fn_ValidarFormatoEmail`
- `fn_ObtenerNombreCategoria`
- `fn_ContarVentasCliente`
- `fn_CalcularDiasDesdeUltimaCompra`
- `fn_DeterminarEstadoLealtad`
- `fn_GenerarSKU`
- `fn_CalcularIVA`
- `fn_ObtenerStockTotalPorCategoria`
- `fn_EstimarFechaEntrega`
- `fn_ConvertirMoneda`
- `fn_ValidarComplejidadContrasena`

## ⚙️ Triggers

El proyecto conserva los 20 procesos funcionales exigidos y agrega validaciones complementarias para:

- Insert/update de email.
- Referidos.
- Stock.
- Totales de venta.
- Cambios de estado.
- Contadores de categorías.
- Auditoría de precios.
- Alertas de inventario.

## ⏰ Eventos

Se mantienen los 20 eventos requeridos para:

- Reportes.
- Limpieza.
- Archivado.
- Promociones.
- Lealtad.
- Reabastecimiento.
- Mantenimiento.
- KPIs.
- Rankings.
- Backup.
- Carritos abandonados.
- Detección de actividad sospechosa.
- Reportes de proveedores.
- Purga segura de soft-delete.

## 🧪 Verificación

Después de ejecutar los scripts:

```sql
SHOW TABLES;

SHOW FUNCTION STATUS
WHERE Db = 'ecommerce';

SHOW PROCEDURE STATUS
WHERE Db = 'ecommerce';

SHOW TRIGGERS;

SHOW EVENTS;

SELECT User, Host
FROM mysql.user
WHERE User LIKE '%_user';
```

### Pruebas recomendadas

1. Intentar insertar precio `<= 0`.
2. Intentar stock negativo.
3. Intentar vender más stock del disponible.
4. Intentar email inválido.
5. Intentar auto-referirse.
6. Intentar devolución superior a la compra.
7. Intentar pagar una venta dos veces.
8. Intentar modificar precio como `inventory_user`.
9. Consultar ventas como usuario de una sucursal.
10. Provocar un error dentro de un procedimiento transaccional y comprobar rollback.

## 🚨 Dependencias del servidor

Hay dos controles que no pueden garantizarse únicamente con SQL portable:

### 1. Auditoría automática de logins fallidos

MySQL Community no expone por defecto todos los fallos de autenticación como filas de una tabla de aplicación. Para auditoría automática real se necesita un mecanismo de auditoría del servidor compatible con el entorno.

### 2. Bloqueo de root remoto

Debe verificarse la existencia de cuentas `root` con hosts remotos y corregirse mediante administración del servidor:

```sql
SELECT User, Host
FROM mysql.user
WHERE User = 'root';
```

No se elimina directamente una cuenta del sistema desde este proyecto.

## 📌 Resultado de la rectificación

El proyecto queda estructuralmente alineado con el enunciado original y con controles adicionales de seguridad, integridad, errores y persistencia.

**Estado del código:** RECTIFICADO.

**Importante:** antes de declarar el sistema como listo para producción debe ejecutarse una prueba real en una instancia MySQL 8.0+ limpia, porque esta revisión estática no sustituye la ejecución contra un servidor.
