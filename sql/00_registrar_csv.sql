-- Registro de los CSV como tabla virtual.
-- Una VIEW no copia datos: cada vez que se consulta, DuckDB lee los CSV de
-- data/raw/ directamente. No hay base de datos que cargar ni archivo .duckdb.
-- union_by_name junta los 8 archivos por nombre de columna (no todas las
-- estaciones tienen las mismas columnas opcionales, como SNWD).
-- Los tipos se fijan a mano: si no, DuckDB infiere TAVG como texto porque
-- las primeras filas de algunos archivos vienen vacías.
CREATE OR REPLACE VIEW clima_crudo AS
SELECT
    STATION,
    NAME,
    "DATE",
    LATITUDE,
    ELEVATION,
    TMAX,
    TMAX_ATTRIBUTES,
    TMIN,
    TMIN_ATTRIBUTES
FROM read_csv(
    'data/raw/*.csv',
    header = true,
    union_by_name = true,
    types = {'TMAX': 'INTEGER', 'TMIN': 'INTEGER', 'TAVG': 'INTEGER', 'PRCP': 'INTEGER'}
);
