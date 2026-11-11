"""
Pre-entrega: Análisis de Datos Meteorológicos con DuckDB e SQL.

Analiza temperaturas diarias de 8 estaciones meteorológicas argentinas
(NOAA GHCN-Daily) consultando los CSV directamente con DuckDB, sin cargarlos
en una base de datos.

Pasos:
1. Descarga: baja los CSV de NOAA a data/raw/ (solo los que faltan).
2. Registro: sql/00 crea una VIEW sobre los CSV (tabla virtual).
3. Limpieza: sql/01 crea la vista "clima" (unidades, flags de calidad, nulos).
4. Análisis: ejecuta las consultas sql/02 a sql/06 y mide cuánto tarda cada una.
5. Comparación: repite dos consultas leyendo Parquet en lugar de CSV.

Uso:
    python analisis_clima.py
"""

import sys
import time
import urllib.request
from pathlib import Path
from urllib.error import URLError

import duckdb

try:
    # Opcional: hace que Python confíe en los certificados del sistema
    # operativo (útil si un antivirus o proxy corporativo inspecciona HTTPS).
    import truststore

    truststore.inject_into_ssl()
except ImportError:
    pass

BASE_DIR = Path(__file__).resolve().parent
DIR_SQL = BASE_DIR / "sql"
DIR_RAW = BASE_DIR / "data" / "raw"
RUTA_PARQUET = BASE_DIR / "data" / "clima_crudo.parquet"

URL_NOAA = "https://www.ncei.noaa.gov/data/global-historical-climatology-network-daily/access/{}.csv"

# Estaciones de norte a sur. Los códigos salen del inventario de NOAA
# (ghcnd-stations.txt).
ESTACIONES = {
    "AR000870470": "Salta Aero",
    "AR000087344": "Córdoba Aero",
    "AR000087418": "Mendoza Aero",
    "AR000875850": "Buenos Aires Observatorio",
    "AR000087715": "Neuquén Aero",
    "ARM00087765": "San Carlos de Bariloche",
    "AR000087860": "Comodoro Rivadavia",
    "ARM00087938": "Ushuaia",
}

CONSULTAS = [
    ("02_calidad_datos.sql", "Calidad de los datos por estación"),
    ("03_cobertura_por_decada.sql", "% de días con temperatura máxima válida, por década"),
    ("04_promedios_mensuales.sql", "Temperatura media mensual (°C), normal 1961-1990"),
    ("05_maximos_historicos.sql", "Récords históricos por estación (°C)"),
    ("06_tendencia.sql", "Temperatura media anual: 1961-1975 vs. 1986-2000 (°C)"),
    ("07_dias_extremos.sql", "Días extremos por año, promedio 1961-2000"),
]
# Las dos que se repiten leyendo Parquet para comparar con CSV
CONSULTAS_COMPARACION = ["04_promedios_mensuales.sql", "05_maximos_historicos.sql"]


def descargar_estaciones() -> None:
    """Baja el CSV de cada estación si todavía no está en data/raw/."""
    DIR_RAW.mkdir(parents=True, exist_ok=True)
    for codigo, nombre in ESTACIONES.items():
        destino = DIR_RAW / f"{codigo}.csv"
        if destino.exists():
            continue
        print(f"  Descargando {nombre} ({codigo})...")
        temporal = destino.with_suffix(".part")
        urllib.request.urlretrieve(URL_NOAA.format(codigo), temporal)
        temporal.replace(destino)
    total_mb = sum(p.stat().st_size for p in DIR_RAW.glob("*.csv")) / 1e6
    print(f"  {len(ESTACIONES)} CSV disponibles en data/raw/ ({total_mb:.1f} MB)")


def ejecutar_archivo(con: duckdb.DuckDBPyConnection, nombre: str) -> float:
    """Ejecuta un .sql que crea vistas y devuelve cuánto tardó."""
    inicio = time.perf_counter()
    con.execute((DIR_SQL / nombre).read_text(encoding="utf-8"))
    return time.perf_counter() - inicio


def consultar(con: duckdb.DuckDBPyConnection, nombre: str):
    """Ejecuta una consulta del directorio sql/ y devuelve (columnas, filas, segundos)."""
    sql = (DIR_SQL / nombre).read_text(encoding="utf-8")
    inicio = time.perf_counter()
    cursor = con.execute(sql)
    filas = cursor.fetchall()
    segundos = time.perf_counter() - inicio
    return [d[0] for d in cursor.description], filas, segundos


def mostrar(columnas: list[str], filas: list[tuple]) -> None:
    """Imprime el resultado como tabla de texto alineada."""
    def formato(valor):
        if valor is None:
            return "-"
        if isinstance(valor, float):
            return f"{valor:.2f}".rstrip("0").rstrip(".")
        return str(valor)

    celdas = [columnas] + [[formato(v) for v in f] for f in filas]
    anchos = [max(len(fila[i]) for fila in celdas) for i in range(len(columnas))]
    for n, fila in enumerate(celdas):
        print("  " + " | ".join(v.ljust(a) for v, a in zip(fila, anchos)))
        if n == 0:
            print("  " + "-+-".join("-" * a for a in anchos))


def comparar_csv_parquet(con: duckdb.DuckDBPyConnection) -> None:
    """Repite dos consultas leyendo el mismo dato desde Parquet en vez de CSV.

    El Parquet guarda los CSV completos (las 16 columnas, no solo las que usa
    el análisis), para que la comparación sea con el mismo contenido. Solo se
    cambia la vista clima_crudo: la vista clima y las consultas siguen
    iguales, porque se apoyan en la vista y no en el archivo.
    """
    con.execute(f"""
        COPY (SELECT * FROM read_csv('data/raw/*.csv', header = true, union_by_name = true,
                                     types = {{'TMAX': 'INTEGER', 'TMIN': 'INTEGER',
                                              'TAVG': 'INTEGER', 'PRCP': 'INTEGER'}}))
        TO '{RUTA_PARQUET.as_posix()}' (FORMAT parquet)
    """)
    mb_csv = sum(p.stat().st_size for p in DIR_RAW.glob("*.csv")) / 1e6
    mb_parquet = RUTA_PARQUET.stat().st_size / 1e6
    print(f"  Tamaño: CSV {mb_csv:.1f} MB -> Parquet {mb_parquet:.1f} MB (mismas 16 columnas)")

    resultados = {}
    for formato in ("CSV", "Parquet"):
        if formato == "Parquet":
            con.execute(f"""
                CREATE OR REPLACE VIEW clima_crudo AS
                SELECT STATION, NAME, "DATE", LATITUDE, ELEVATION,
                       TMAX, TMAX_ATTRIBUTES, TMIN, TMIN_ATTRIBUTES
                FROM read_parquet('{RUTA_PARQUET.as_posix()}')
            """)
        for nombre in CONSULTAS_COMPARACION:
            # Mejor de 3 corridas, para no medir la primera lectura en frío
            resultados[formato, nombre] = min(consultar(con, nombre)[2] for _ in range(3))

    for nombre in CONSULTAS_COMPARACION:
        csv, parquet = resultados["CSV", nombre], resultados["Parquet", nombre]
        print(f"  {nombre}: CSV {csv * 1000:.0f} ms | Parquet {parquet * 1000:.0f} ms "
              f"({csv / parquet:.1f}x más rápido)")

    # Se vuelve a dejar la vista apuntando a los CSV originales
    ejecutar_archivo(con, "00_registrar_csv.sql")


def main() -> int:
    print("=== 1. Descarga (NOAA GHCN-Daily) ===")
    try:
        descargar_estaciones()
    except URLError as e:
        print(f"[error] No se pudo descargar de NOAA: {e.reason}")
        print(f"        Revisá la conexión o copiá los CSV a mano en {DIR_RAW}")
        return 1

    # Base en memoria: no se crea ningún archivo .duckdb
    con = duckdb.connect()
    # read_csv('data/raw/*.csv') usa rutas relativas a la carpeta del proyecto
    con.execute(f"SET file_search_path = '{BASE_DIR.as_posix()}'")

    print("\n=== 2. Registro de los CSV y limpieza ===")
    t_registro = ejecutar_archivo(con, "00_registrar_csv.sql")
    t_limpieza = ejecutar_archivo(con, "01_limpiar.sql")
    filas_crudas = con.execute("SELECT count(*) FROM clima_crudo").fetchone()[0]
    filas_limpias = con.execute("SELECT count(*) FROM clima").fetchone()[0]
    print(f"  Vistas creadas en {(t_registro + t_limpieza) * 1000:.0f} ms "
          f"(no se lee ningún dato hasta consultar)")
    print(f"  clima_crudo: {filas_crudas:,} días | clima: {filas_limpias:,} días "
          f"con al menos una temperatura válida")

    print("\n=== 3. Consultas analíticas ===")
    for nombre, titulo in CONSULTAS:
        columnas, filas, segundos = consultar(con, nombre)
        print(f"\n[{nombre}] {titulo} — {segundos * 1000:.0f} ms")
        mostrar(columnas, filas)

    print("\n=== 4. CSV vs. Parquet ===")
    comparar_csv_parquet(con)

    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
