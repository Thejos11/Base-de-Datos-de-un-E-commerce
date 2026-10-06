WITH fecha_ref AS (
    SELECT MAX(fecha_venta) AS fecha_referencia
    FROM ventas
    WHERE estado NOT IN ('Cancelado', 'Pendiente de Pago')
),

devuelto_por_venta AS (
    SELECT
        dv.id_venta,
        SUM(d.monto) AS monto_devuelto
    FROM devoluciones d
    JOIN detalle_ventas dv ON dv.id_detalle = d.id_detalle
    GROUP BY dv.id_venta
),

compras_validas AS (
    SELECT
        v.id_venta,
        v.id_cliente,
        v.fecha_venta,
        v.total - COALESCE(dpv.monto_devuelto, 0) AS valor_neto
    FROM ventas v
    LEFT JOIN devuelto_por_venta dpv ON dpv.id_venta = v.id_venta
    WHERE v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
),

metricas_cliente AS (
    SELECT
        c.id_cliente,
        CONCAT(c.nombre, ' ', c.apellido)                          AS cliente,
        DATEDIFF(MAX(fr.fecha_referencia), MAX(cv.fecha_venta))    AS recencia,
        COUNT(cv.id_venta)                                         AS frecuencia,
        SUM(cv.valor_neto)                                         AS monetario
    FROM clientes c
    JOIN compras_validas cv ON cv.id_cliente = c.id_cliente
    CROSS JOIN fecha_ref fr
    WHERE c.eliminado_en IS NULL
    GROUP BY c.id_cliente, c.nombre, c.apellido
),

puntuaciones AS (
    SELECT
        mc.*,
        CAST(LEAST(4, FLOOR(4 * PERCENT_RANK() OVER (ORDER BY recencia   DESC)) + 1) AS SIGNED) AS R_score,
        CAST(LEAST(4, FLOOR(4 * PERCENT_RANK() OVER (ORDER BY frecuencia ASC))  + 1) AS SIGNED) AS F_score,
        CAST(LEAST(4, FLOOR(4 * PERCENT_RANK() OVER (ORDER BY monetario  ASC))  + 1) AS SIGNED) AS M_score
    FROM metricas_cliente mc
),

segmentos AS (
    SELECT
        p.*,
        (R_score + F_score + M_score)                      AS RFM_Score,
        CONCAT(R_score, F_score, M_score)                  AS RFM_Code,
        CASE
            WHEN R_score >= 3 AND F_score >= 3 AND M_score >= 3
                THEN 'Campeones'
            WHEN R_score <= 2 AND (F_score >= 3 OR M_score >= 3)
                THEN 'En Riesgo'
            WHEN R_score >= 3 AND F_score >= 3
                THEN 'Leales'
            WHEN R_score >= 3 AND F_score <= 2
                THEN 'Nuevos'
            ELSE 'Ocasionales'
        END                                                AS segmento
    FROM puntuaciones p
)

SELECT
    id_cliente,
    cliente,
    recencia,
    frecuencia,
    monetario,
    R_score,
    F_score,
    M_score,
    RFM_Score,
    RFM_Code,
    segmento
FROM segmentos
ORDER BY RFM_Score DESC, monetario DESC, id_cliente;

/* =====================================================================
   EXPLICACIÓN
   =====================================================================

   QUÉ HACE
   Clasifica a los clientes según cómo compran, con tres datos:
     R (Recencia)   : hace cuántos días compró por última vez.
     F (Frecuencia) : cuántos pedidos ha hecho.
     M (Monetario)  : cuánto dinero ha gastado en total.
   Cada dato recibe una nota de 1 a 4 (4 = mejor, 1 = peor) y, con las
   tres notas, cada cliente queda en un segmento.

   CÓMO EJECUTARLO (MySQL 8.0 o superior)
     mysql -u root -p ecommerce < rfm_segmentacion.sql

   QUÉ PEDIDOS CUENTAN
   Todos menos los 'Cancelado' y los 'Pendiente de Pago', porque ninguno
   de los dos representa una venta real. Es el mismo criterio que ya usa
   el resto del proyecto.

   QUÉ CLIENTES NO APARECEN
   - Los que nunca han comprado (no hay nada que medir).
   - Los eliminados (sus datos están anonimizados).

   CÓMO SE CALCULA CADA PARTE
   fecha_ref
     Fecha de comparación: la fecha de la última compra de toda la tienda.
     Se usa en vez de la fecha de hoy para que el resultado no cambie con
     el paso del tiempo.
   devuelto_por_venta
     Dinero devuelto en cada pedido, para descontarlo del gasto.
   compras_validas
     Una fila por pedido válido, con su valor (el total del pedido menos lo
     devuelto). Se toma el total ya guardado en cada pedido, sin recorrer
     sus productos uno a uno, para no contar un pedido varias veces.
   metricas_cliente
     Por cliente: días desde su última compra, número de pedidos y gasto
     total.
   puntuaciones
     Pone a los clientes en fila y reparte las notas por posición:
     el 25 % de abajo recibe 1, el siguiente 2, luego 3 y el 25 % de
     arriba recibe 4. Clientes con el mismo valor reciben la misma nota.
     Importante: en Recencia el orden va al revés, porque tener MENOS días
     sin comprar es mejor. Así el cliente más reciente siempre saca 4.
   segmentos
     RFM_Score = R + F + M (de 3 a 12).
     RFM_Code  = las tres notas juntas, por ejemplo '434'.
     Segmento  = se revisan las reglas en este orden y gana la primera que
                 se cumple:
       1. Campeones  : compran reciente, seguido y gastan mucho
                       (R, F y M de 3 o más).
       2. En Riesgo  : llevan tiempo sin comprar (R de 1 o 2) pero antes
                       compraban seguido o gastaban mucho (F o M de 3+).
       3. Leales     : compran reciente y seguido (R y F de 3 o más).
       4. Nuevos     : compraron hace poco pero pocas veces (R de 3+,
                       F de 1 o 2).
       5. Ocasionales: todos los demás.

   RESULTADO
   Una fila por cliente, ordenada de mejor a peor (RFM_Score y, si hay
   empate, mayor gasto).
   ===================================================================== */
