# Referencias científicas

## Política

- **No se inventan datasets ni percentiles.** Ninguna comparación poblacional se mostrará sin una fuente verificada con los campos de la plantilla.
- Se distinguen valores medidos directamente (laboratorio) de estimaciones del Apple Watch; no se comparan entre sí sin advertirlo.
- Las puntuaciones de HÅLSYN son estimaciones de bienestar, no medidas clínicamente validadas.

## Estado (Fase 8)

Dos tablas incorporadas, copiadas de la fuente y verificadas fila a fila (`ReferenceLibrary.swift`, generado; no editar a mano). Los valores del modo demo siguen siendo sintéticos.

## Referencias usadas como umbrales en HealthScoreEngine (Fase 3)

Orientan los umbrales; **no validan** la puntuación de HÅLSYN en conjunto.

| Uso | Referencia | Qué se toma |
|---|---|---|
| Sueño 7–9 h (adultos) | Watson NF, et al. *Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep Medicine and Sleep Research Society.* Sleep. 2015;38(6):843–844. | ≥ 7 h por noche de forma regular en adultos; el rango 7–9 h se usa como referencia de máxima puntuación. |
| 150 min/semana de actividad | Bull FC, et al. *World Health Organization 2020 guidelines on physical activity and sedentary behaviour.* Br J Sports Med. 2020;54(24):1451–1462. | 150–300 min/semana de actividad moderada (o equivalente) en adultos. Se usan los "minutos de ejercicio" de Apple como aproximación. |
| Pasos/día según la edad | Paluch AE, et al. *Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts.* Lancet Public Health. 2022;7(3):e219–e228. doi:10.1016/S2468-2667(21)00302-9 | El beneficio se estabiliza aproximadamente entre 6.000–8.000 pasos (≥ 60 años) y 8.000–10.000 (< 60 años). Se usa el centro de cada rango: 7.000 (≥ 60) y 9.000 (< 60); sin edad, 8.000. Edad del perfil de la app o, si no, de Salud (`HealthScoreConfiguration.stepsReference(age:)`). |
| Carga aguda:crónica | Gabbett TJ. *The training—injury prevention paradox: should athletes be training smarter and harder?* Br J Sports Med. 2016;50(5):273–280. | Concepto de comparar carga reciente con habitual; zona 0,8–1,3. |
| Críticas al cociente | Impellizzeri FM, et al. *Acute:Chronic Workload Ratio: Conceptual Issues and Fundamental Pitfalls.* Int J Sports Physiol Perform. 2020;15(6):907–913. | Motivo del peso bajo (15 %) y de no tratarlo como predictor de lesiones. |
| HRV y FC en reposo frente a la media personal | Práctica habitual de comparar con la línea basal individual en lugar de valores poblacionales, dada la gran variabilidad entre personas. | Comparación con la media de 28 días; sin percentiles poblacionales (Fase 8). |

Pendiente: revisar cada cita con su texto completo antes de la publicación y registrar DOI/PMID.

## Life's Essential 8 — salud cardiovascular (`CardiovascularHealthEngine`)

Lloyd-Jones DM, et al. *Life's Essential 8: Updating and Enhancing the American Heart Association's Construct of Cardiovascular Health: A Presidential Advisory From the American Heart Association.* Circulation. 2022;146(5):e18–e43. doi:10.1161/CIR.0000000000001078

Ocho componentes de 0 a 100 (tablas para adultos) y su media simple. Alta ≥ 80, moderada 50–79, baja < 50.

| Componente | Fuente en la app | Puntos |
|---|---|---|
| Actividad física | Minutos de ejercicio de Apple, 7 días completos anteriores (≥ 4 con dato) | ≥150: 100 · 120–149: 90 · 90–119: 80 · 60–89: 60 · 30–59: 40 · 1–29: 20 · 0: 0 |
| Sueño | Media de las noches de 2 semanas (≥ 7) | 7–<9 h: 100 · 9–<10: 90 · 6–<7: 70 · 5–<6 o ≥10: 40 · 4–<5: 20 · <4: 0 |
| IMC | Último peso de Salud + altura del perfil | <25: 100 · 25–29,9: 70 · 30–34,9: 30 · 35–39,9: 15 · ≥40: 0 |
| Nicotina | Escrito por el usuario | Nunca: 100 · dejado ≥5 años: 75 · 1–<5: 50 · <1 año o vapeo: 25 · actual: 0 · humo en casa: −20 |
| Colesterol no-HDL | Escrito (total − HDL, mg/dL) | <130: 100 · 130–159: 60 · 160–189: 40 · 190–219: 20 · ≥220: 0 · tratado: −20 |
| Glucosa | Escrito (ayunas o HbA1c) | Sin diabetes: <100 / <5,7 %: 100 · 100–125 / 5,7–6,4 %: 60. Con diabetes (HbA1c): <7: 40 · 7–7,9: 30 · 8–8,9: 20 · 9–9,9: 10 · ≥10: 0 |
| Presión arterial | Escrito (mmHg) | <120/<80: 100 · 120–129/<80: 75 · 130–139 o 80–89: 50 · 140–159 o 90–99: 25 · ≥160 o ≥100: 0 · tratada: −20 |
| Alimentación | Cuestionario MEPA de 16 preguntas (raciones al día o a la semana), criterios de la tabla C del suplemento de la AHA | MEPA 15–16: 100 · 12–14: 80 · 8–11: 50 · 4–7: 25 · 0–3: 0 |

MEPA: Cerwinske LA, Rasmussen HE, Volgman AS, Tangney CC. *Evaluation of a dietary screener: the Mediterranean Eating Pattern for Americans tool.* J Hum Nutr Diet. 2017;30(5):596–603. doi:10.1111/jhn.12451. El cuestionario es © Christy Tangney y Heather Rasmussen (Rush University Medical Center): **pedir permiso de uso antes de publicar en la App Store**. Preguntas traducidas y porciones en unidades métricas (3 oz ≈ 85 g, 1 oz ≈ 30 g). Criterio de alcohol de la tabla C: más de 0 y menos de 2 al día (hombres) o de 1 al día (mujeres); sin sexo en el perfil se usa el de mujeres.

Limitaciones: los minutos de ejercicio de Apple no distinguen intensidad (la AHA cuenta doble la vigorosa); con componentes sin dato se promedian los disponibles (mínimo 4) y la interfaz lo indica como parcial. Pendiente: verificar las tablas con el texto completo antes de publicar.

## Regularidad del sueño (`SleepRegularityIndex`)

- Definición: Phillips AJK, et al. *Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing.* Sci Rep. 2017;7:3216. doi:10.1038/s41598-017-03171-4. SRI = 200 × (minutos en el mismo estado que 24 h después / minutos comparados) − 100.
- Contexto: Windred DP, et al. *Sleep regularity is a stronger predictor of mortality risk than sleep duration: a prospective cohort study.* Sleep. 2024;47(1):zsad253. doi:10.1093/sleep/zsad253. UK Biobank, 60.977 adultos con acelerómetro; mediana 81,0 (RIC 73,8–86,3); los cuatro quintiles más regulares, 20–48 % menos mortalidad que el más irregular.
- En la app: épocas de 1 minuto, ventana de mediodía a mediodía por noche, solo pares de noches consecutivas (mínimo 5). Solo sueño nocturno (sin siestas). El valor depende del método de cálculo, por lo que se presenta como tendencia y con el contexto del estudio, no como percentil.

## Referencias por edad (Fase 8)

### VO₂ máx. — FRIEND 2015 (`friend-2015-treadmill`)

| Campo | Valor |
|---|---|
| Fuente | Kaminsky LA, Arena R, Myers J. *Reference Standards for Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise National Database.* Mayo Clin Proc. 2015;90(11):1515–1523. DOI 10.1016/j.mayocp.2015.07.026 |
| Tabla | Tabla 3 (cinta), percentiles 5, 10, 25, 50, 75, 90 y 95 |
| Población | 7.783 pruebas, 8 laboratorios de EE. UU. (2014–2015), 20–79 años, sin enfermedad cardiovascular ni EPOC conocidas |
| Método | Prueba de esfuerzo máxima en cinta con análisis de gases |
| Grupos | Por sexo y décadas de 20–29 a 70–79 (12 filas, con su n) |
| Compatible con Apple Watch | Con advertencia: el reloj da una estimación submáxima |
| Limitaciones mostradas | Estimación frente a laboratorio; muestra de conveniencia de EE. UU.; la actualización de 2022 da valores 1,5–4,6 mL·kg⁻¹·min⁻¹ más bajos (su tabla no se pudo verificar); sin datos para 80+ |
| Licencia | Copia de autor en PMC (uso legítimo, *fair use*); copyright Elsevier/Mayo. **Revisar con asesoría antes de publicar en la App Store (Fase 10).** La versión de 2022 es CC BY-NC-ND. |

### FC en reposo — NHANES 1999–2008 (`nhanes-1999-2008-pulse`)

| Campo | Valor |
|---|---|
| Fuente | Ostchega Y, Porter KS, Hughes J, Dillon CF, Nwankwo T. *Resting pulse rate reference data for children, adolescents, and adults: United States, 1999–2008.* National Health Statistics Reports n.º 41. NCHS; 2011. https://www.cdc.gov/nchs/data/nhsr/nhsr041.pdf |
| Tabla | Tablas 2 y 3 (adultos), percentiles 1–99; en 80+ faltan algunos extremos y se omiten |
| Población | Muestra representativa de EE. UU., 14.200 adultos; excluye embarazo, infección probable, pulso irregular, tiroides alterada y fármacos que cambian la FC |
| Método | Pulso radial contado a mano 30 s (×2), sentado tras ~4 min de reposo |
| Grupos | Por sexo: 20–39, 40–59, 60–79 y 80+ (16–19 años no se incluyen) |
| Compatible con Apple Watch | Con advertencia: el reloj calcula la FC en reposo de otra forma |
| Licencia | Dominio público (se cita la fuente) |

### HRV — sin referencia

No se muestran percentiles de HRV: el SDNN del Apple Watch sale de lecturas ópticas cortas (~1 min) a horas y posturas arbitrarias, y las normas publicadas usan ECG de 5 min en decúbito (o 24 h) y dan media ± DE. No son comparables.

### Cómo se calcula la posición (`ReferencePercentileEngine`)

- Se elige la fila del sexo y del grupo de edad del usuario; sin edad, sin sexo o fuera de la cobertura → no se compara.
- Entre dos percentiles publicados se interpola linealmente; fuera de la tabla se dice "por debajo del P5"/"por encima del P95", sin extrapolar.
- La frase es neutra: "unas N de cada 100 personas tienen un valor más bajo"; la dirección (más alto es mejor en VO₂, más bajo en FC) se explica aparte, sin juicio clínico.
- Edad y sexo los escribe el usuario o se copian de Salud; se guardan solo en el iPhone. En demo sin perfil se usa un perfil de ejemplo (hombre de 35) etiquetado.

## Plantilla de dataset

```yaml
id:
fuente:            # publicación u organismo
referencia:        # DOI / PMID / URL oficial
año:
población:
país:
rango_edad:
sexo:
método_medición:   # p. ej. prueba de esfuerzo con análisis de gases
unidad:
tamaño_muestra:
percentiles:       # por grupo de edad/sexo
limitaciones:
compatible_con_apple_watch:   # sí / con advertencia / no, y por qué
```

## Edad fisiológica

Arquitectura prevista, pero **sin fórmula** hasta disponer de un modelo validado aplicable a los datos del Apple Watch. Mientras tanto solo se mostrarán indicadores y percentiles.

## Zonas cardíacas (Fase 5)

- **Método de la reserva cardíaca**: Karvonen MJ, Kentala E, Mustala O. *The effects of training on heart rate; a longitudinal study.* Ann Med Exp Biol Fenn. 1957;35(3):307–315. Intensidad = FC reposo + (FC máx − FC reposo) × fracción.
- **Modelo de 5 zonas (50/60/70/80/90 %)**: convención extendida en entrenamiento de resistencia y en dispositivos deportivos; **no** es un estándar clínico. Las guías del ACSM (*ACSM's Guidelines for Exercise Testing and Prescription*) describen la intensidad por % de FC máx. y % de reserva con rangos parecidos, pero sus categorías no coinciden exactamente con estas 5 zonas.
- **FC máxima**: HÅLSYN **no la estima por la edad** (las fórmulas tipo 220 − edad tienen un error individual grande). Solo usa un valor introducido por el usuario o el máximo registrado en sus carreras, y lo dice.
- La interfaz presenta las zonas como guía de entrenamiento, nunca como indicación médica.

## Ciclismo — CYKEL (`PowerAnalysis`, `PowerZones`, `FTPEstimator`)

- **FTP, potencia normalizada, factor de intensidad y TSS**: Allen H, Coggan AR, McGregor S. *Training and Racing with a Power Meter.* 3.ª ed. VeloPress; 2019 (ISBN 978-1-937715-93-9, https://search.worldcat.org/isbn/9781937715939).
  - FTP ≈ 0,95 × potencia media de un esfuerzo máximo de 20 min.
  - Potencia normalizada: media móvil de 30 s sobre la serie de 1 Hz, a la cuarta potencia, media y raíz cuarta.
  - IF = NP / FTP.
  - TSS = (s × NP × IF) / (FTP × 3600) × 100, de modo que 1 h al FTP = 100.
  - NP, IF y TSS son marcas de TrainingPeaks. La interfaz usa nombres descriptivos ("Ponderada", "Intensidad", "Carga") y lo indica.
- **Zonas de potencia**: Coggan AR. *Power training levels* (TrainingPeaks), https://www.trainingpeaks.com/learn/articles/power-training-levels/.
  - Techos en % del FTP: 55, 75, 90, 105 y 120.
  - Coggan define L6 como >121 % y L7 como esfuerzos máximos cortos, sin porcentaje. El corte del 150 % entre Z6 y Z7 es una convención de las apps y la interfaz lo dice.
- **Validez del FTP** (por qué se presenta como estimación):
  - Borszcz FK, Tramontin AF, Costa VP. *Int J Sports Physiol Perform.* 2019;14(8):1029–1035, doi:10.1123/ijspp.2018-0572. Frente al MLSS: sesgo 1,4 % ± 9,2 % (límites de acuerdo del 95 %).
  - Valenzuela PL, et al. *Int J Sports Physiol Perform.* 2018;13(10):1293–1298, doi:10.1123/ijspp.2018-0008. En ciclistas recreativos el FTP queda por debajo del umbral de lactato.
  - Otras referencias revisadas y no citadas en la interfaz:
    - Inglis EC, et al. 2020 (doi:10.1123/ijspp.2019-0214): el FTP sobreestima el MLSS.
    - MacInnis MJ, et al. 2019 (doi:10.1123/ijspp.2018-0100): en su muestra, la potencia de 60 min ≈ 0,90 × la de 20 min.
- **Estimación en la app**: 95 % de la mejor media de 20 min seguidos de las salidas con potencia de las últimas 6 semanas (`FTPEstimate.windowDays = 42`).
  - Solo vale si esos 20 min fueron un esfuerzo máximo, y así se dice.
  - Prioridad del FTP: el del usuario, después el que guarda el Apple Watch en Salud (`cyclingFunctionalThresholdPower`) y, por último, la estimación.
- **Serie de potencia**: cada lectura vale hasta la siguiente. Un hueco de más de 5 s (pausa o sensor perdido) corta la serie y no cuenta ni como 0 ni como potencia. Los 0 W reales (rueda libre) sí cuentan.
- **Zonas cardíacas en bici**: Roecker K, Striegel H, Dickhuth HH. *Int J Sports Med.* 2003;24(3):173–178, doi:10.1055/s-2003-39087. Los umbrales de FC no se trasladan entre correr y pedalear. CYKEL usa las zonas de SPRING y advierte que son orientativas.
- **Bici y salud** (asociación, no causa): Celis-Morales CA, et al. *BMJ.* 2017;357:j1456, doi:10.1136/bmj.j1456.
  - UK Biobank, 263.450 adultos, mediana de seguimiento 5 años.
  - Ir al trabajo en bici: HR 0,59 (IC 95 % 0,42–0,83) para mortalidad por cualquier causa.
- **Datos que no se inventan**:
  - Potencia y cadencia solo con sensores Bluetooth emparejados con el reloj (watchOS 10+).
  - En interior no hay distancia sin un sensor de velocidad.
  - El desnivel se calcula con la altitud GPS (con histéresis de 3 m), se marca como aproximado y se guarda en Salud (`HKMetadataKeyElevationAscended`).
