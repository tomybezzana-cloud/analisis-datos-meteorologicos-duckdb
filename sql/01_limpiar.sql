-- Limpieza: vista "clima" con temperaturas en °C y sin valores dudosos.
--
-- 1. Unidades: GHCN-Daily guarda las temperaturas en décimas de °C (286 = 28,6).
-- 2. Flag de calidad: el campo *_ATTRIBUTES tiene el formato "MFLAG,QFLAG,SFLAG".
--    Si QFLAG no está vacío, el valor no pasó un control de calidad de NOAA
--    (G = salto anómalo, X = fuera de rango, I = inconsistente, D = duplicado).
--    Esos valores se pasan a NULL. Ejemplo: Neuquén, 13/07/1964, TMAX = 97 °C.
-- 3. Consistencia: si la máxima es menor que la mínima, alguna de las dos está
--    mal y no se sabe cuál, así que se anulan ambas.
-- 4. Nulos: NO se imputan. Inventar temperaturas en una serie temporal sesgaría
--    los promedios y los récords. AVG, MAX y MIN ignoran los NULL, y las
--    consultas exigen un mínimo de días con datos para que un mes o un año
--    cuente (ver 03 y 05).
-- 5. Se descartan los días sin ninguna temperatura válida.
-- 6. tmedia = (tmax + tmin) / 2, la media diaria clásica en climatología. Si
--    falta alguna de las dos, queda NULL. TAVG no se usa: NOAA la calcula
--    distinto (promedio horario) y solo existe en algunos años, así que
--    mezclarla rompería la comparación entre períodos.
CREATE OR REPLACE VIEW clima AS
WITH con_flags AS (
    SELECT
        STATION                              AS estacion_id,
        replace(NAME, ', AR', '')            AS estacion,
        "DATE"                               AS fecha,
        CASE WHEN split_part(TMAX_ATTRIBUTES, ',', 2) = '' THEN TMAX / 10.0 END AS tmax,
        CASE WHEN split_part(TMIN_ATTRIBUTES, ',', 2) = '' THEN TMIN / 10.0 END AS tmin
    FROM clima_crudo
),
consistente AS (
    SELECT
        estacion_id,
        estacion,
        fecha,
        CASE WHEN tmax < tmin THEN NULL ELSE tmax END AS tmax,
        CASE WHEN tmax < tmin THEN NULL ELSE tmin END AS tmin
    FROM con_flags
)
SELECT
    *,
    (tmax + tmin) / 2 AS tmedia
FROM consistente
WHERE tmax IS NOT NULL
   OR tmin IS NOT NULL;
