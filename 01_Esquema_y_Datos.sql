-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto: Base de Datos para un E-commerce
-- Motor objetivo: MySQL 8.0+
-- Contenido: Creación de esquema, tablas y carga de datos de ejemplo
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce;
CREATE DATABASE ecommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ecommerce;

-- ---------------------------------------------------------------------
-- Tabla: categorias
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL UNIQUE,
    descripcion  TEXT NULL,
    num_productos INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: proveedores
-- ---------------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor      INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL,
    email_contacto    VARCHAR(150) NULL UNIQUE,
    telefono_contacto VARCHAR(30) NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: productos
-- ---------------------------------------------------------------------
CREATE TABLE productos (
    id_producto     INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL UNIQUE,
    descripcion     TEXT NULL,
    precio          DECIMAL(12,2) NOT NULL CHECK (precio > 0),
    costo           DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (costo >= 0),
    stock           INT NOT NULL DEFAULT 0 CHECK (stock >= 0),
    stock_minimo    INT NOT NULL DEFAULT 5 CHECK (stock_minimo >= 0),
    sku             VARCHAR(50) NOT NULL UNIQUE,
    id_categoria    INT NULL,
    id_proveedor    INT NULL,
    fecha_creacion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion DATETIME NULL,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    veces_visto     INT NOT NULL DEFAULT 0,
    peso_kg         DECIMAL(8,2) NOT NULL DEFAULT 0 CHECK (peso_kg >= 0),
    ubicacion       VARCHAR(100) NULL,
    eliminado_en   DATETIME NULL,
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_producto_proveedor
        FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Indices para productos
CREATE INDEX idx_producto_categoria ON productos(id_categoria);
CREATE INDEX idx_producto_proveedor ON productos(id_proveedor);
CREATE INDEX idx_producto_activo ON productos(activo);
CREATE INDEX idx_producto_nombre ON productos(nombre);

-- ---------------------------------------------------------------------
-- Tabla: clientes
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente       INT AUTO_INCREMENT PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL,
    apellido         VARCHAR(100) NOT NULL,
    email            VARCHAR(150) NOT NULL UNIQUE,
    contrasena       VARCHAR(255) NOT NULL,
    direccion_envio  VARCHAR(255) NULL,
    ciudad           VARCHAR(100) NULL,
    region           VARCHAR(60) NULL,
    fecha_nacimiento DATE NULL,
    fecha_registro   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_ultimo_pedido DATETIME NULL,
    total_gastado    DECIMAL(14,2) NOT NULL DEFAULT 0,
    nivel_lealtad    VARCHAR(20) NOT NULL DEFAULT 'Bronce',
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    eliminado_en     DATETIME NULL,
    id_referido_por  INT NULL,
    CONSTRAINT fk_cliente_referido
        FOREIGN KEY (id_referido_por) REFERENCES clientes(id_cliente)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Indice para clientes
CREATE INDEX idx_cliente_email ON clientes(email);
CREATE INDEX idx_cliente_activo ON clientes(activo);

-- ---------------------------------------------------------------------
-- Tabla: ventas
-- ---------------------------------------------------------------------
CREATE TABLE ventas (
    id_venta     INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    id_sucursal  INT NOT NULL DEFAULT 1,
    fecha_venta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado       ENUM('Pendiente de Pago','Pagado','Procesando','Enviado','Entregado','Cancelado')
                 NOT NULL DEFAULT 'Pendiente de Pago',
    total        DECIMAL(14,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    direccion_envio VARCHAR(255) NULL,
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Indices para ventas
CREATE INDEX idx_venta_cliente ON ventas(id_cliente);
CREATE INDEX idx_venta_fecha ON ventas(fecha_venta);
CREATE INDEX idx_venta_estado ON ventas(estado);

-- ---------------------------------------------------------------------
-- Tabla: detalle_ventas
-- ---------------------------------------------------------------------
CREATE TABLE detalle_ventas (
    id_detalle                INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                  INT NOT NULL,
    id_producto                INT NOT NULL,
    cantidad                   INT NOT NULL CHECK (cantidad > 0),
    precio_unitario_congelado  DECIMAL(12,2) NOT NULL,
    subtotal                  DECIMAL(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario_congelado) STORED,
    fecha_venta               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uk_detalle_venta_producto UNIQUE (id_venta, id_producto)
) ENGINE=InnoDB;

-- Indices para detalle_ventas
CREATE INDEX idx_detalle_venta ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto ON detalle_ventas(id_producto);

-- ---------------------------------------------------------------------
-- Vista para consultas: v_lineas_venta (usada en consultas avanzadas y eventos)
-- ---------------------------------------------------------------------
CREATE VIEW v_lineas_venta AS
SELECT 
    id_detalle,
    id_venta,
    id_producto,
    cantidad,
    precio_unitario_congelado,
    subtotal,
    fecha_venta
FROM detalle_ventas;

-- ---------------------------------------------------------------------
-- Tablas de soporte para triggers / eventos / auditoría
-- ---------------------------------------------------------------------
CREATE TABLE log_cambios_precio (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_producto   INT NOT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL,
    usuario       VARCHAR(100) NOT NULL,
    fecha_cambio  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE log_nuevos_clientes (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    fecha_alta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE log_cambio_estado_pedido (
    id_log        INT AUTO_INCREMENT PRIMARY KEY,
    id_venta      INT NOT NULL,
    estado_anterior VARCHAR(30) NULL,
    estado_nuevo    VARCHAR(30) NOT NULL,
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
) ENGINE=InnoDB;

CREATE TABLE alertas_stock (
    id_alerta    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    stock_actual INT NOT NULL,
    fecha        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    atendida     BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

CREATE TABLE ventas_archivadas (
    id_venta    INT NOT NULL,
    id_cliente  INT NOT NULL,
    fecha_venta DATETIME NOT NULL,
    estado      VARCHAR(30) NOT NULL,
    total       DECIMAL(14,2) NOT NULL,
    fecha_archivado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_venta),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE log_permisos (
    id_log      INT AUTO_INCREMENT PRIMARY KEY,
    detalle     VARCHAR(255) NOT NULL,
    fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE log_intentos_login (
    id_log     INT AUTO_INCREMENT PRIMARY KEY,
    usuario    VARCHAR(100) NOT NULL,
    host_origen VARCHAR(150) NULL,
    exitoso    BOOLEAN NOT NULL,
    fecha_intento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE reporte_ventas_semanales (
    id_reporte    INT AUTO_INCREMENT PRIMARY KEY,
    semana_inicio DATE NOT NULL,
    semana_fin    DATE NOT NULL,
    num_ventas    INT NOT NULL,
    total_vendido  DECIMAL(14,2) NOT NULL,
    fecha_generado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE kpis_mensuales (
    anio_mes       VARCHAR(7) PRIMARY KEY,
    num_ventas     INT NOT NULL,
    total_vendido  DECIMAL(14,2) NOT NULL,
    nuevos_clientes INT NOT NULL,
    ticket_promedio DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE resumen_ventas_diarias (
    id_resumen   INT AUTO_INCREMENT PRIMARY KEY,
    fecha        DATE NOT NULL UNIQUE,
    total_ventas DECIMAL(14,2) NOT NULL,
    num_ordenes  INT NOT NULL
) ENGINE=InnoDB;

-- Tablas de respaldo para persistencia y recuperación
CREATE TABLE backup_productos LIKE productos;
CREATE TABLE backup_ventas LIKE ventas;
CREATE TABLE backup_detalle_ventas LIKE detalle_ventas;
CREATE TABLE backup_clientes LIKE clientes;

-- ---------------------------------------------------------------------
-- Tablas adicionales para funcionalidades referenciadas
-- ---------------------------------------------------------------------

-- Tabla para promociones (usada en consultas avanzadas y eventos)
CREATE TABLE promociones (
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NULL,
    codigo VARCHAR(30) NOT NULL UNIQUE,
    descuento_pct DECIMAL(5,2) NOT NULL DEFAULT 0,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- Tabla para carrito de compras (usada en consultas y eventos)
CREATE TABLE carrito_items (
    id_carrito_item INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad INT NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    fecha_agregado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Tabla para visitas a productos (usada en consultas)
CREATE TABLE visitas_producto (
    id_visita INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente INT NULL,
    fecha_visita DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto),
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- Tabla para reseñas (usada en procedimientos)
CREATE TABLE resenas (
    id_resena INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente INT NOT NULL,
    calificacion TINYINT NOT NULL CHECK (calificacion BETWEEN 1 AND 5),
    comentario TEXT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE,
    UNIQUE KEY uk_resena_producto_cliente (id_producto, id_cliente)
) ENGINE=InnoDB;

-- Tabla para pagos (usada en procedimientos)
CREATE TABLE pagos (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    metodo VARCHAR(30) NOT NULL,
    monto DECIMAL(14,2) NOT NULL,
    estado ENUM('Pendiente','Aprobado','Rechazado','Cancelado') NOT NULL DEFAULT 'Pendiente',
    fecha_pago DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
) ENGINE=InnoDB;

-- Tabla para devoluciones (usada en procedimientos)
CREATE TABLE devoluciones (
    id_devolucion INT AUTO_INCREMENT PRIMARY KEY,
    id_detalle INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    monto DECIMAL(12,2) NOT NULL,
    motivo VARCHAR(200) NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_detalle) REFERENCES detalle_ventas(id_detalle)
) ENGINE=InnoDB;

-- Tabla para creditos de cliente (usada en procedimientos)
CREATE TABLE creditos_cliente (
    id_credito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    motivo VARCHAR(200) NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usado BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

-- Tabla para ajustes de stock (usada en procedimientos)
CREATE TABLE ajustes_stock (
    id_ajuste INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    stock_anterior INT NOT NULL,
    stock_nuevo INT NOT NULL,
    motivo VARCHAR(200) NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    fecha DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
) ENGINE=InnoDB;

-- Tabla para cola de notificaciones (usada en procedimientos)
CREATE TABLE cola_notificaciones (
    id_notificacion INT AUTO_INCREMENT PRIMARY KEY,
    evento VARCHAR(100) NOT NULL,
    id_venta INT NULL,
    payload JSON NOT NULL,
    fecha_creacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    procesada BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

-- Tabla para tasas de cambio (usada en funciones)
CREATE TABLE tasas_cambio (
    id_tasa INT AUTO_INCREMENT PRIMARY KEY,
    moneda VARCHAR(3) NOT NULL UNIQUE,
    tasa DECIMAL(14,6) NOT NULL,
    fecha_actualizacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Tabla para sucursales (referenciada en ventas)
CREATE TABLE sucursales (
    id_sucursal INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    direccion VARCHAR(255) NOT NULL,
    ciudad VARCHAR(100) NOT NULL,
    telefono VARCHAR(30) NULL
) ENGINE=InnoDB;

-- Insertar sucursal por defecto
INSERT INTO sucursales (nombre, direccion, ciudad, telefono) VALUES
('Sucursal Principal', 'Calle 1 #1-1', 'Bogotá', '3000000000');

ALTER TABLE ventas
    ADD CONSTRAINT fk_venta_sucursal
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
    ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------
-- Datos de ejemplo
-- ---------------------------------------------------------------------
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos electrónicos y gadgets'),
('Ropa', 'Prendas de vestir para todas las edades'),
('Hogar', 'Artículos para el hogar y decoración'),
('Deportes', 'Equipamiento e indumentaria deportiva'),
('General', 'Categoría por defecto para productos sin clasificar');

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechSupply S.A.', 'contacto@techsupply.com', '3001234567'),
('Moda Global Ltda.', 'ventas@modaglobal.com', '3007654321'),
('HogarPlus', 'info@hogarplus.com', '3009988776'),
('SportGear Inc.', 'sales@sportgear.com', '3005554433');

INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, sku, id_categoria, id_proveedor, peso_kg, ubicacion) VALUES
('Laptop UltraSlim 14"', 'Laptop liviana con 16GB RAM y SSD 512GB', 3200000, 2400000, 15, 5, 'SKU-ELEC-001', 1, 1, 1.8, 'A-01'),
('Auriculares Bluetooth X200', 'Auriculares inalámbricos con cancelación de ruido', 250000, 150000, 40, 10, 'SKU-ELEC-002', 1, 1, 0.3, 'A-02'),
('Smartwatch Fit Pro', 'Reloj inteligente con monitor cardíaco', 480000, 300000, 25, 8, 'SKU-ELEC-003', 1, 1, 0.2, 'A-03'),
('Camiseta Algodón Premium', 'Camiseta 100% algodón, varios colores', 65000, 30000, 100, 20, 'SKU-ROPA-001', 2, 2, 0.2, 'B-01'),
('Jean Clásico Azul', 'Jean corte recto talla estándar', 120000, 60000, 60, 15, 'SKU-ROPA-002', 2, 2, 0.5, 'B-02'),
('Chaqueta Impermeable', 'Chaqueta resistente al agua para exteriores', 210000, 110000, 30, 10, 'SKU-ROPA-003', 2, 2, 0.8, 'B-03'),
('Juego de Sábanas Queen', 'Set de sábanas 100% algodón tamaño Queen', 150000, 80000, 20, 5, 'SKU-HOGAR-001', 3, 3, 2.0, 'C-01'),
('Lámpara de Mesa LED', 'Lámpara moderna regulable', 90000, 45000, 35, 10, 'SKU-HOGAR-002', 3, 3, 0.5, 'C-02'),
('Balón de Fútbol Profesional', 'Balón oficial talla 5', 110000, 55000, 45, 10, 'SKU-DEP-001', 4, 4, 0.4, 'D-01'),
('Bicicleta Montaña R29', 'Bicicleta todo terreno con 21 velocidades', 1450000, 950000, 8, 3, 'SKU-DEP-002', 4, 4, 15.0, 'D-02');

INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio, ciudad, region, fecha_nacimiento, fecha_registro, total_gastado, nivel_lealtad) VALUES
('Ana', 'Gómez', 'ana.gomez@correo.com', 'fdd54c4281806e5720a23fd6e5554526c630668eee4d047ac75af7be76ea5163', 'Calle 10 #5-20', 'Bogotá', 'Cundinamarca', '1990-05-14', '2025-01-10 09:00:00', 0, 'Bronce'),
('Carlos', 'Ramírez', 'carlos.ramirez@correo.com', '5b6b17cfa0b144fa3a349c5a5284bf26c33c693e9dbddfce4dc6d26db646d997', 'Cra 45 #12-34', 'Medellín', 'Antioquia', '1985-11-02', '2025-02-15 14:30:00', 0, 'Bronce'),
('Laura', 'Martínez', 'laura.martinez@correo.com', 'c4310a08611d6efc9752e382c967ed1959e5f66a91335760efcd23e557af0630', 'Av 3 #22-10', 'Cali', 'Valle del Cauca', '1993-07-21', '2025-03-05 10:15:00', 0, 'Bronce'),
('Diego', 'Torres', 'diego.torres@correo.com', '92fc8fa90337abe365856fa0cff7769338ed737ba18b1f4c3b885c571e098eac', 'Calle 80 #9-40', 'Bucaramanga', 'Santander', '1998-01-30', '2025-04-20 16:45:00', 0, 'Bronce'),
('María', 'López', 'maria.lopez@correo.com', '31d51230ad75356a09996d61ae763380d7203c1c793d016333de31140a7cac5d', 'Cra 15 #30-05', 'Barranquilla', 'Atlántico', '1988-09-09', '2025-05-11 11:20:00', 0, 'Bronce');

-- Ventas de ejemplo
INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, total) VALUES
(1, 1, '2025-06-01 10:00:00', 'Entregado', 0),
(2, 1, '2025-06-10 15:30:00', 'Entregado', 0),
(1, 1, '2025-07-02 09:20:00', 'Enviado', 0),
(3, 1, '2025-07-15 12:00:00', 'Procesando', 0),
(4, 1, '2025-08-05 17:10:00', 'Entregado', 0),
(5, 1, '2025-08-20 08:45:00', 'Pendiente de Pago', 0);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado, fecha_venta) VALUES
(1, 1, 1, 3200000, '2025-06-01 10:00:00'),
(1, 2, 2, 250000, '2025-06-01 10:00:00'),
(2, 4, 3, 65000, '2025-06-10 15:30:00'),
(2, 9, 1, 110000, '2025-06-10 15:30:00'),
(3, 3, 1, 480000, '2025-07-02 09:20:00'),
(4, 5, 2, 120000, '2025-07-15 12:00:00'),
(4, 6, 1, 210000, '2025-07-15 12:00:00'),
(5, 10, 1, 1450000, '2025-08-05 17:10:00'),
(6, 7, 1, 150000, '2025-08-20 08:45:00'),
(6, 8, 2, 90000, '2025-08-20 08:45:00');

-- Actualizar totales de venta según el detalle
UPDATE ventas v
SET total = (
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
    FROM detalle_ventas d
    WHERE d.id_venta = v.id_venta
);

UPDATE ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
SET v.direccion_envio = c.direccion_envio
WHERE v.direccion_envio IS NULL;

UPDATE clientes c
SET c.total_gastado = COALESCE((
    SELECT SUM(v.total)
    FROM ventas v
    WHERE v.id_cliente = c.id_cliente
      AND v.estado NOT IN ('Cancelado','Pendiente de Pago')
), 0);

-- Actualizar fecha_ultimo_pedido para clientes con ventas
UPDATE clientes c
JOIN (
    SELECT id_cliente, MAX(fecha_venta) AS last_order
    FROM ventas
    WHERE estado NOT IN ('Cancelado', 'Pendiente de Pago')
    GROUP BY id_cliente
) v ON v.id_cliente = c.id_cliente
SET c.fecha_ultimo_pedido = v.last_order;

UPDATE clientes c
SET c.nivel_lealtad = CASE
    WHEN c.total_gastado >= 5000 THEN 'Oro'
    WHEN c.total_gastado >= 1500 THEN 'Plata'
    ELSE 'Bronce'
END;

-- Insertar algunas tasas de cambio
INSERT INTO tasas_cambio (moneda, tasa) VALUES
('USD', 0.00025),
('EUR', 0.00023),
('COP', 1.00000);

-- Actualizar contador de productos por categoría
UPDATE categorias c
SET num_productos = (
    SELECT COUNT(*)
    FROM productos p
    WHERE p.id_categoria = c.id_categoria
);
