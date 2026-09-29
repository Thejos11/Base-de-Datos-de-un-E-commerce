-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- 20 consultas de análisis y reporteo para el negocio.
-- Motor objetivo: MySQL 8.0+
-- Ejecutar con:  mysql -u root -p ecommerce < 02_Consultas_Avanzadas.sql
-- =====================================================================
USE ecommerce;

-- 1. Top 10 Productos Más Vendidos (por ingresos generados)
SELECT p.id_producto, p.nombre,
       SUM(dv.cantidad)  AS unidades_vendidas,
       SUM(dv.subtotal)  AS ingresos_generados
FROM detalle_ventas dv
JOIN productos p ON p.id_producto = dv.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_generados DESC
LIMIT 10;

-- 2. Productos con Bajas Ventas (10% inferior por ingresos, incluye los que no se han vendido)
SET @limite_bajas_ventas = CAST(GREATEST(1, CEIL((SELECT COUNT(*) FROM productos) * 0.10)) AS UNSIGNED);
PREPARE consulta_bajas_ventas FROM
 'SELECT p.id_producto, p.nombre, COALESCE(SUM(dv.subtotal), 0) AS ingresos_generados
  FROM productos p
  LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
  GROUP BY p.id_producto, p.nombre
  ORDER BY ingresos_generados ASC
  LIMIT ?';
EXECUTE consulta_bajas_ventas USING @limite_bajas_ventas;
DEALLOCATE PREPARE consulta_bajas_ventas;

-- 3. Clientes VIP: Top 5 por valor de vida (LTV = gasto total histórico)
SELECT c.id_cliente, CONCAT(c.nombre, ' ', c.apellido) AS cliente, c.total_gastado
FROM clientes c
ORDER BY c.total_gastado DESC
LIMIT 5;

-- 4. Análisis de Ventas Mensuales
SELECT DATE_FORMAT(v.fecha_venta, '%Y-%m') AS anio_mes,
       COUNT(DISTINCT v.id_venta) AS num_ventas,
       SUM(v.total) AS total_vendido
FROM ventas v
WHERE v.estado <> 'Cancelado'
GROUP BY anio_mes
ORDER BY anio_mes;

-- 5. Crecimiento de Clientes: nuevos clientes por trimestre
SELECT CONCAT(YEAR(fecha_registro), '-T', QUARTER(fecha_registro)) AS trimestre,
       COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY trimestre
ORDER BY trimestre;

-- 6. Tasa de Compra Repetida (% de clientes con más de una compra efectiva)
SELECT
  ROUND(100 * SUM(CASE WHEN compras > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_clientes_recurrentes
FROM (
  SELECT v.id_cliente, COUNT(*) AS compras
  FROM ventas v
  WHERE v.estado <> 'Cancelado'
  GROUP BY v.id_cliente
) t;

-- 7. Productos Comprados Juntos Frecuentemente (pares dentro de la misma venta)
SELECT p1.nombre AS producto_a, p2.nombre AS producto_b, COUNT(*) AS veces_juntos
FROM detalle_ventas d1
JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto < d2.id_producto
JOIN productos p1 ON p1.id_producto = d1.id_producto
JOIN productos p2 ON p2.id_producto = d2.id_producto
GROUP BY p1.nombre, p2.nombre
ORDER BY veces_juntos DESC
LIMIT 10;

-- 8. Rotación de Inventario por Categoría (unidades vendidas / stock actual)
SELECT cat.nombre AS categoria,
       COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas,
       SUM(p.stock) AS stock_actual,
       ROUND(COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0), 2) AS indice_rotacion
FROM categorias cat
JOIN productos p ON p.id_categoria = cat.id_categoria
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY cat.nombre
ORDER BY indice_rotacion DESC;

-- 9. Productos que Necesitan Reabastecimiento (stock por debajo del mínimo)
SELECT id_producto, nombre, stock, stock_minimo
FROM productos
WHERE stock < stock_minimo AND activo = TRUE
ORDER BY (stock_minimo - stock) DESC;

-- 10. Análisis de Carrito Abandonado (agregado hace más de 48h, cliente sin compra desde entonces)
SELECT ci.id_cliente, CONCAT(cl.nombre, ' ', cl.apellido) AS cliente,
       p.nombre AS producto, ci.cantidad, ci.fecha_agregado
FROM carrito_items ci
JOIN clientes cl ON cl.id_cliente = ci.id_cliente
JOIN productos p ON p.id_producto = ci.id_producto
WHERE ci.fecha_agregado < DATE_SUB(NOW(), INTERVAL 48 HOUR)
  AND NOT EXISTS (
        SELECT 1 FROM ventas v
        WHERE v.id_cliente = ci.id_cliente AND v.fecha_venta > ci.fecha_agregado)
ORDER BY ci.fecha_agregado;

-- 11. Rendimiento de Proveedores (por ingresos generados de sus productos)
SELECT pr.id_proveedor, pr.nombre,
       COALESCE(SUM(dv.subtotal), 0) AS ingresos_generados,
       COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas
FROM proveedores pr
LEFT JOIN productos p ON p.id_proveedor = pr.id_proveedor
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;

-- 12. Análisis Geográfico de Ventas (por ciudad del cliente)
SELECT c.ciudad, COUNT(DISTINCT v.id_venta) AS num_ventas, SUM(v.total) AS total_vendido
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY total_vendido DESC;

-- 13. Ventas por Hora del Día (horas pico)
SELECT HOUR(fecha_venta) AS hora, COUNT(*) AS num_ventas
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY hora
ORDER BY num_ventas DESC;

-- 14. Impacto de Promociones (ventas del producto antes / durante / después de la campaña)
SELECT pm.codigo,
       SUM(CASE WHEN v.fecha_venta <  pm.fecha_inicio THEN dv.cantidad ELSE 0 END) AS unidades_antes,
       SUM(CASE WHEN v.fecha_venta BETWEEN pm.fecha_inicio AND pm.fecha_fin THEN dv.cantidad ELSE 0 END) AS unidades_durante,
       SUM(CASE WHEN v.fecha_venta >  pm.fecha_fin THEN dv.cantidad ELSE 0 END) AS unidades_despues
FROM promociones pm
JOIN detalle_ventas dv ON dv.id_producto = pm.id_producto
JOIN ventas v ON v.id_venta = dv.id_venta AND v.estado <> 'Cancelado'
GROUP BY pm.codigo;

-- 15. Análisis de Cohort (retención de clientes mes a mes desde su primera compra)
WITH primera_compra AS (
  SELECT id_cliente, MIN(DATE_FORMAT(fecha_venta, '%Y-%m-01')) AS mes_cohort
  FROM ventas WHERE estado <> 'Cancelado'
  GROUP BY id_cliente
)
SELECT pc.mes_cohort,
       TIMESTAMPDIFF(MONTH, pc.mes_cohort, DATE_FORMAT(v.fecha_venta, '%Y-%m-01')) AS mes_desde_cohort,
       COUNT(DISTINCT v.id_cliente) AS clientes_activos
FROM ventas v
JOIN primera_compra pc ON pc.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY pc.mes_cohort, mes_desde_cohort
ORDER BY pc.mes_cohort, mes_desde_cohort;

-- 16. Margen de Beneficio por Producto
SELECT id_producto, nombre, precio, costo,
       (precio - costo) AS margen_absoluto,
       ROUND(100 * (precio - costo) / precio, 2) AS margen_pct
FROM productos
ORDER BY margen_pct DESC;

-- 17. Tiempo Promedio Entre Compras (por cliente, en días)
SELECT ROUND(AVG(dias_entre_compras), 1) AS promedio_dias_entre_compras
FROM (
  SELECT id_cliente,
         DATEDIFF(fecha_venta, LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta)) AS dias_entre_compras
  FROM ventas
  WHERE estado <> 'Cancelado'
) t
WHERE dias_entre_compras IS NOT NULL;

-- 18. Productos Más Vistos vs. Comprados
SELECT p.id_producto, p.nombre,
       COUNT(DISTINCT vp.id_visita) AS num_visitas,
       COALESCE(SUM(dv.cantidad), 0) AS unidades_compradas,
       ROUND(COALESCE(SUM(dv.cantidad), 0) / NULLIF(COUNT(DISTINCT vp.id_visita), 0), 3) AS tasa_conversion
FROM productos p
LEFT JOIN visitas_producto vp ON vp.id_producto = p.id_producto
LEFT JOIN detalle_ventas dv ON dv.id_producto = p.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY num_visitas DESC;

-- 19. Segmentación de Clientes (RFM: Recencia, Frecuencia, Monetario)
SELECT c.id_cliente, CONCAT(c.nombre, ' ', c.apellido) AS cliente,
       DATEDIFF(CURDATE(), c.fecha_ultimo_pedido) AS recencia_dias,
       COUNT(v.id_venta) AS frecuencia,
       c.total_gastado AS monetario,
       CASE
         WHEN DATEDIFF(CURDATE(), c.fecha_ultimo_pedido) <= 60 AND c.total_gastado >= 4000 THEN 'Campeón'
         WHEN DATEDIFF(CURDATE(), c.fecha_ultimo_pedido) <= 90 THEN 'Cliente Activo'
         WHEN c.fecha_ultimo_pedido IS NULL THEN 'Sin Compras'
         ELSE 'En Riesgo'
       END AS segmento_rfm
FROM clientes c
LEFT JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
GROUP BY c.id_cliente, c.nombre, c.apellido, c.fecha_ultimo_pedido, c.total_gastado
ORDER BY monetario DESC;

-- 20. Predicción de Demanda Simple (promedio mensual histórico proyectado al mes próximo, por categoría)
SELECT cat.nombre AS categoria,
       ROUND(AVG(ventas_mes.unidades_mes), 1) AS demanda_proyectada_prox_mes
FROM categorias cat
JOIN productos p ON p.id_categoria = cat.id_categoria
JOIN (
    SELECT dv.id_producto, DATE_FORMAT(dv.fecha_venta, '%Y-%m') AS mes, SUM(dv.cantidad) AS unidades_mes
    FROM detalle_ventas dv
    GROUP BY dv.id_producto, mes
) ventas_mes ON ventas_mes.id_producto = p.id_producto
GROUP BY cat.nombre
ORDER BY demanda_proyectada_prox_mes DESC;
