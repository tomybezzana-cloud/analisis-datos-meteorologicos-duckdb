# Análisis de Datos Meteorológicos con DuckDB e SQL

Análisis de **más de 200.000 días de temperaturas** de 8 estaciones
meteorológicas argentinas (de Salta a Ushuaia, desde 1908) usando
**DuckDB** como motor analítico embebido. Las consultas SQL se ejecutan
**directamente sobre los archivos CSV**: no hay base de datos que instalar ni
datos que cargar, y no se genera ningún archivo `.duckdb`.

## Estructura

```
├── analisis_clima.py          # Descarga los CSV, ejecuta los .sql con DuckDB y mide tiempos
├── sql/
│   ├── 00_registrar_csv.sql   # VIEW sobre los CSV (tabla virtual)
│   ├── 01_limpiar.sql         # Limpieza: unidades, flags de calidad, nulos
│   ├── 02_calidad_datos.sql   # Consulta 1: conteos de calidad por estación
│   ├── 03_cobertura_por_decada.sql  # Consulta 2: % de días con datos por década (PIVOT)
│   ├── 04_promedios_mensuales.sql   # Consulta 3: temperatura media mensual (PIVOT)
│   ├── 05_maximos_historicos.sql    # Consulta 4: récords por estación (arg_max / arg_min)
│   ├── 06_tendencia.sql       # Consulta 5: cambio de temperatura entre dos períodos
│   └── 07_dias_extremos.sql   # Consulta 6: días de calor, heladas y noches tropicales
├── requirements.txt
└── .gitignore                 # Excluye data/ (CSV descargados) y cualquier *.duckdb
```

## Datos

[NOAA GHCN-Daily](https://www.ncei.noaa.gov/products/land-based-station/global-historical-climatology-network-daily)
(Global Historical Climatology Network), un CSV por estación, descargados
desde `https://www.ncei.noaa.gov/data/global-historical-climatology-network-daily/access/<estación>.csv`.

| Código NOAA | Estación |
|---|---|
| AR000870470 | Salta Aero |
| AR000087344 | Córdoba Aero |
| AR000087418 | Mendoza Aero |
| AR000875850 | Buenos Aires Observatorio |
| AR000087715 | Neuquén Aero |
| ARM00087765 | San Carlos de Bariloche |
| AR000087860 | Comodoro Rivadavia |
| ARM00087938 | Ushuaia |

Se usan `TMAX` y `TMIN` (temperatura máxima y mínima diaria). En estos
archivos vienen en **décimas de °C** (`286` = 28,6 °C) y cada valor trae un
campo `*_ATTRIBUTES` con flags de calidad.

Los CSV (24 MB en total) **no se suben al repositorio**: el script los
descarga la primera vez en `data/raw/`, que está en el `.gitignore`.

## Instalación y ejecución

Requiere Python 3.10 o superior. Probado con Python 3.13 y DuckDB 2.0.0.

```bash
git clone https://github.com/tomybezzana-cloud/analisis-datos-meteorologicos-duckdb.git
cd analisis-datos-meteorologicos-duckdb

# (Opcional) entorno virtual
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

pip install -r requirements.txt
python analisis_clima.py
```

El script imprime cada etapa, el resultado de cada consulta y cuánto tardó.
Si NOAA no responde, muestra un mensaje de error y termina con código 1. En
ese caso se pueden bajar los CSV a mano desde la URL de arriba y guardarlos
en `data/raw/`.

Las consultas también se pueden ejecutar desde la
[CLI de DuckDB](https://duckdb.org/docs/installation/) (después de correr el
script una vez, para tener los CSV). Abriendo `duckdb` en la carpeta del
proyecto:

```sql
.read sql/00_registrar_csv.sql
.read sql/01_limpiar.sql
.read sql/05_maximos_historicos.sql
```

## Cómo funciona

### 1. Registro de los CSV como tabla virtual

```sql
CREATE OR REPLACE VIEW clima_crudo AS
SELECT STATION, NAME, "DATE", LATITUDE, ELEVATION,
       TMAX, TMAX_ATTRIBUTES, TMIN, TMIN_ATTRIBUTES
FROM read_csv('data/raw/*.csv', header = true, union_by_name = true,
              types = {'TMAX': 'INTEGER', 'TMIN': 'INTEGER', ...});
```

- `read_csv('data/raw/*.csv')` lee **los 8 archivos como si fueran una sola
  tabla**, con un comodín.
- Es una `VIEW`: no copia datos. Crear la vista tarda milisegundos y DuckDB
  lee los CSV recién cuando se consulta.
- La conexión es `duckdb.connect()` sin nombre de archivo, es decir, una base
  **en memoria**. Al terminar el script no queda nada en disco salvo los CSV
  originales.
- Los tipos se fijan a mano. Si no, DuckDB infiere `TAVG` como texto, porque
  las primeras filas de algunos archivos vienen vacías.

### 2. Limpieza (vista `clima`)

| Problema | Ejemplo real | Tratamiento |
|---|---|---|
| Unidades en décimas de °C | `286` | Se divide por 10 |
| Valores que no pasaron el control de calidad de NOAA (flag `QFLAG` no vacío) | Neuquén, 13/07/1964: **97 °C** (flag `X`, fuera de rango) | Se pasan a NULL (91 días en total) |
| Máxima menor que la mínima | 25 días, 21 de ellos en Mendoza | Se anulan las dos: no se sabe cuál está mal |
| Días sin ninguna temperatura | 10.133 días | Se descartan |
| Nulos en general | Hasta 57% de días sin máxima (Bariloche) | **No se imputan** (ver abajo) |

**¿Por qué no se imputan los nulos?** En una serie temporal de clima,
completar un día faltante con un promedio inventa datos y suaviza
justamente los extremos que se quieren medir (récords, olas de calor). En
cambio:

- `AVG`, `MAX` y `MIN` ignoran los NULL;
- cada consulta exige un **mínimo de cobertura** para que un mes (≥ 20 días)
  o un año (≥ 330 días) cuente. Así un mes con 5 días medidos no se toma
  como representativo.

La temperatura media diaria se calcula como `(tmax + tmin) / 2`, la
definición clásica en climatología. Si falta alguna de las dos, queda NULL.
`TAVG` no se usa: NOAA la calcula de otra forma (promedio de lecturas
horarias) y solo existe para algunos años, así que mezclarla rompería las
comparaciones entre períodos.

### 3. Consultas analíticas

| # | Archivo | Tipo | Técnicas de SQL |
|---|---|---|---|
| 1 | `02_calidad_datos.sql` | Conteos | `count(*) FILTER (WHERE ...)`, `split_part` |
| 2 | `03_cobertura_por_decada.sql` | Conteos | `PIVOT`, `date_diff`, subconsulta escalar |
| 3 | `04_promedios_mensuales.sql` | Promedios | CTE, `HAVING` en dos niveles, `PIVOT` |
| 4 | `05_maximos_historicos.sql` | Máximos | `arg_max` / `arg_min` (fecha del récord sin JOIN) |
| 5 | `06_tendencia.sql` | Filtrado complejo | `AVG(...) FILTER`, `HAVING` con varias condiciones |
| 6 | `07_dias_extremos.sql` | Filtrado complejo | Conteos condicionales por año y promedio entre años |

## Resultados

### Calidad y cobertura: el hallazgo que condiciona todo el análisis

| Estación | Desde | Días | % sin máxima | % sin mínima | Con flag de calidad | Máx. < mín. |
|---|---|---:|---:|---:|---:|---:|
| Buenos Aires Observ. | 1908-09-02 | 39.691 | 6,4 | 0,8 | 46 | 0 |
| Comodoro Rivadavia | 1956-02-01 | 25.343 | 14,9 | 4,9 | 5 | 3 |
| Salta Aero | 1956-02-01 | 24.666 | 19,0 | 5,9 | 4 | 0 |
| Córdoba Aero | 1956-02-02 | 25.391 | 22,0 | 8,3 | 2 | 0 |
| Neuquén Aero | 1956-08-01 | 25.022 | 18,0 | 5,4 | 3 | 1 |
| Mendoza Aero | 1957-06-30 | 24.555 | 21,5 | 6,9 | 25 | 21 |
| Ushuaia | 1957-06-30 | 15.499 | 53,5 | 36,2 | 2 | 0 |
| S. C. de Bariloche | 1957-06-30 | 19.912 | 57,5 | 25,9 | 4 | 0 |

Todas las series llegan hasta el 24/08/2025. Porcentaje de días con máxima
válida, por década:

| Estación | 1960s | 1970s | 1980s | 1990s | 2000s | 2010s | 2020s |
|---|---:|---:|---:|---:|---:|---:|---:|
| Buenos Aires Observ. | 100 | 100 | 99 | 100 | **44** | **44** | **47** |
| Comodoro Rivadavia | 98 | 100 | 99 | 100 | 74 | 53 | 50 |
| Córdoba Aero | 86 | 99 | 93 | 100 | 69 | 45 | 47 |
| Mendoza Aero | 92 | 98 | 96 | 100 | 69 | 46 | 46 |
| Neuquén Aero | 82 | 100 | 100 | 99 | 74 | 50 | 49 |
| Salta Aero | 91 | 100 | 100 | 100 | 69 | 36 | 44 |
| S. C. de Bariloche | 9 | 6 | 32 | 48 | 53 | 50 | 52 |
| Ushuaia | 2 | 2 | 14 | 44 | 49 | 50 | 46 |

**Desde 2001 falta aproximadamente la mitad de los días** en todas las
estaciones. Como la caída es simultánea en las 8, todo indica que es una
limitación de cómo llegan los datos de Argentina al archivo de NOAA, y no de
las estaciones en sí. Por eso:

- los promedios y la tendencia se calculan sobre **1961-2000**, el período
  con datos casi completos;
- la normal climatológica 1991-2020 **no se puede calcular** de forma
  confiable (solo 13 de sus 30 años tienen cobertura suficiente);
- Bariloche y Ushuaia quedan fuera de los promedios, porque nunca tuvieron
  una década completa.

### Temperatura media mensual (°C), normal 1961-1990

| Estación | Ene | Feb | Mar | Abr | May | Jun | Jul | Ago | Sep | Oct | Nov | Dic |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Mendoza Aero | 25,2 | 23,8 | 20,8 | 16,8 | 12,5 | 8,9 | 8,6 | 11,0 | 13,8 | 18,2 | 21,6 | 24,3 |
| Buenos Aires Observ. | 24,8 | 23,7 | 21,6 | 18,0 | 14,8 | 11,7 | 11,4 | 12,7 | 14,6 | 17,4 | 20,3 | 23,1 |
| Córdoba Aero | 23,4 | 22,7 | 20,7 | 17,7 | 14,8 | 11,3 | 11,2 | 12,9 | 15,1 | 18,3 | 20,7 | 22,6 |
| Neuquén Aero | 23,1 | 22,1 | 18,6 | 14,0 | 10,0 | 6,8 | 6,4 | 8,6 | 11,4 | 15,2 | 19,1 | 22,0 |
| Salta Aero | 21,8 | 21,0 | 19,7 | 17,1 | 14,3 | 11,5 | 11,5 | 13,4 | 15,5 | 18,9 | 20,7 | 21,7 |
| Comodoro Rivadavia | 19,4 | 18,8 | 16,5 | 13,5 | 9,8 | 7,0 | 6,6 | 8,0 | 10,3 | 12,9 | 16,1 | 18,0 |

- **Mendoza tiene el verano más cálido** (25,2 °C en enero), por encima de
  Buenos Aires y Salta. Lo explica el clima seco: con poca humedad, las
  máximas suben mucho.
- **Salta tiene la menor diferencia entre verano e invierno** (10,3 °C entre
  enero y julio), por su latitud más baja. Su verano es más fresco que el de
  Buenos Aires por la altura (1.246 m).
- En todas las estaciones **julio es el mes más frío**, salvo Salta, donde
  junio y julio empatan.

### Récords históricos (°C)

| Estación | Récord máx. | Fecha | Récord mín. | Fecha | Amplitud |
|---|---:|---|---:|---|---:|
| Mendoza Aero | 44,4 | 2003-01-30 | -7,8 | 1976-07-10 | 52,2 |
| Buenos Aires Observ. | 43,3 | 1957-01-29 | -5,4 | 1918-07-09 | 48,7 |
| Córdoba Aero | 42,4 | 2011-12-22 | -8,3 | 2017-07-17 | 50,7 |
| Neuquén Aero | 42,3 | 1980-01-21 | -12,8 | 1961-06-13 | 55,1 |
| Comodoro Rivadavia | 40,2 | 2012-01-15 | -8,5 | 1964-06-25 | 48,7 |
| Salta Aero | 39,9 | 1972-11-28 | -9,4 | 1966-08-05 | 49,3 |
| S. C. de Bariloche | 36,4 | 2024-01-23 | -25,4 | 2017-07-16 | 61,8 |
| Ushuaia | 27,5 | 2004-02-09 | -13,9 | 1958-06-18 | 41,4 |

- Sin la limpieza, el récord de Neuquén habría sido **97 °C** (un error de
  carga que NOAA ya tenía marcado).
- **Bariloche tiene la mayor amplitud** (61,8 °C entre su récord de calor y
  el de frío). Su mínima de -25,4 °C (16/07/2017) cae un día antes del
  récord de frío de Córdoba (17/07/2017), lo que apunta a una misma ola
  polar. El valor pasó los controles de NOAA, pero no lo verifiqué contra
  los registros del Servicio Meteorológico Nacional.
- Los récords posteriores a 2000 pueden estar **subestimados**: falta la
  mitad de los días, y el día más extremo puede ser justo uno de los que no
  están.

### Tendencia: temperatura media anual, 1961-1975 vs. 1986-2000 (°C)

| Estación | Años válidos 61-75 | Años válidos 86-00 | 1961-1975 | 1986-2000 | Diferencia |
|---|---:|---:|---:|---:|---:|
| Mendoza Aero | 13 | 15 | 16,91 | 17,43 | **+0,52** |
| Buenos Aires Observ. | 15 | 15 | 17,71 | 18,16 | **+0,45** |
| Neuquén Aero | 12 | 15 | 14,62 | 15,02 | **+0,40** |
| Comodoro Rivadavia | 14 | 15 | 13,02 | 13,13 | +0,12 |
| Salta Aero | 14 | 15 | 17,17 | 17,27 | +0,10 |
| Córdoba Aero | 14 | 12 | 17,68 | 17,56 | -0,12 |

**5 de las 6 estaciones se calentaron** entre los dos períodos, entre 0,1 y
0,5 °C en 25 años. Mendoza, Buenos Aires y Neuquén muestran el aumento más
claro. Córdoba es la excepción (-0,12 °C), una diferencia chica que puede
deberse a cambios en el entorno de la estación o a los 2 años de menos que
tiene en el segundo período. Son solo 6 estaciones y no es un análisis
estadístico formal, pero la dirección coincide con el calentamiento
registrado en la región.

### Días extremos por año (promedio 1961-2000)

| Estación | Años | Días ≥ 35 °C | Días de helada (< 0 °C) | Noches tropicales (mín. ≥ 20 °C) | Amplitud diaria (°C) |
|---|---:|---:|---:|---:|---:|
| Neuquén Aero | 37 | 13,5 | **53,4** | 4,8 | 14,8 |
| Mendoza Aero | 36 | **18,9** | 24,7 | 24,9 | 13,9 |
| Salta Aero | 39 | 3,9 | 20,7 | 1,3 | 13,6 |
| Córdoba Aero | 36 | 9,0 | 14,4 | 13,2 | 13,0 |
| Comodoro Rivadavia | 39 | 1,4 | 21,5 | 1,5 | 10,4 |
| Buenos Aires Observ. | 40 | 4,1 | 1,5 | **50,1** | **9,2** |

- **Buenos Aires casi no tiene heladas** (1,5 días por año), pero tiene **50
  noches tropicales**: la cercanía del Río de la Plata y la propia ciudad
  frenan el enfriamiento nocturno. Por eso también tiene la menor amplitud
  diaria (9,2 °C).
- **Neuquén es la más extrema**: 53 días de helada por año y, aun así, 13,5
  días de 35 °C o más. Tiene la mayor amplitud diaria (14,8 °C), típica del
  clima seco y continental.
- **Mendoza es la ciudad con más calor extremo** (casi 19 días al año por
  encima de 35 °C).

## Tiempos de respuesta

Medidos en una notebook con Windows 11, DuckDB 2.0.0 y los 8 CSV (24,3 MB,
200.079 filas):

| Etapa | Tiempo |
|---|---:|
| Crear las vistas (registro + limpieza) | ~180 ms |
| Cada consulta analítica, leyendo los CSV | 200-410 ms |
| Script completo (incluye la comparación con Parquet) | ~4,5 s |

Cada consulta **vuelve a leer y parsear los 24 MB de CSV** y aun así responde
en alrededor de 0,2 segundos.

**CSV vs. Parquet.** El script convierte los mismos CSV (las 16 columnas) a
Parquet y repite dos consultas cambiando solo la vista `clima_crudo`:

| | CSV | Parquet |
|---|---:|---:|
| Tamaño en disco | 24,3 MB | **1,5 MB** |
| Consulta 3 (promedios mensuales) | 238 ms | **50 ms** (4,8x) |
| Consulta 4 (récords) | 225 ms | **24 ms** (9,3x) |

Parquet es columnar y comprimido: DuckDB lee solo las columnas que usa la
consulta y no tiene que convertir texto a números. Si el análisis se
repitiera seguido, convertir los CSV a Parquet una vez sería la primera
optimización.

## Checklist de la consigna

1. **Script funcional con DuckDB:** `analisis_clima.py` (`import duckdb`).
2. **Al menos tres consultas analíticas:** seis, con promedios, conteos,
   máximos y filtrados complejos (`FILTER`, `HAVING` en varios niveles,
   `PIVOT`).
3. **README con instrucciones para replicar:** este archivo.
4. **Consultas directas sobre archivos:** `read_csv('data/raw/*.csv')` dentro
   de una `VIEW`. El Parquet de la comparación también se consulta
   directamente con `read_parquet`.
5. **Sin archivos binarios de base de datos:** la conexión es en memoria y el
   `.gitignore` excluye `*.duckdb` por las dudas.
6. **`requirements.txt`:** incluido (`duckdb`).

---

Tomás Bezzana
