# Evolución del motor de rendimiento y recuperación: informe (0.10.0 (107))

Versiones: RacePerformanceModel 1.6 · IndividualAdaptationModel 1.0 · RecoveryEngine 0.4. HealthScoreEngine no cambia. Formato de exportación 4.

## Qué cambia para el usuario (caso real del 8/11)

| Tema | Antes | Ahora |
|---|---|---|
| FC máxima en uso | 186, reemplazaba en silencio la configurada (182) | 182, la tuya, con un aviso y la opción «Usar la validada» (186) |
| FC registrada / validada | — | 189 / 186; el 189 del 23/6 aparece una sola vez y queda como pico aislado |
| Adaptación | 50 % Daniels y 50 % tendencia | «Adaptación individual: todavía no estimable»: 2 pruebas en 2 días, se usa la referencia |
| Escenarios | Tasas fijas (1 punto cada 4, 6 u 8 semanas) | Percentiles 10, 50 y 90 de la distribución predictiva |
| Factor de cumplimiento | 1,0 desde el 90 % | (c − 0,4) ÷ 0,6. Con un 92,9 %, 0,88: proyección algo más lenta |
| Recuperación del 7/11 | 83–84 | 80–81: el componente más bajo no queda compensado del todo |
| Siesta del 7/11 (1,52 h) | Sumada a la noche del 8 | Atribuida al 7 |

Ningún cambio se hizo para mejorar resultados. Los cambios de valores van hacia estimaciones más prudentes.

## Pruebas

509 tests del paquete. Los nuevos cubren:

- **FC máxima**: caso real, pico aislado, pico transitorio, valor provisional, salto implausible y configuración conservada.
- **Intensidad**: jerarquía de evidencia e intensidad percibida frente al plan.
- **Sueño**: siesta del 7, episodios posteriores a la hora del cálculo y duplicados.
- **Adaptación**:
  - dos pruebas no son una tendencia;
  - tres pruebas muy juntas tampoco;
  - tendencias positivas y negativas;
  - anomalía con menos peso;
  - más pruebas, más peso.
- **Proyección**: escenarios de la distribución, rampa continua, tasas negativas acotadas y backtest sin datos futuros.
- **Validación**: error por horizonte y «Datos insuficientes para validar».
- **Recuperación 0.4**:
  - HRV muy alta;
  - no compensación;
  - enfermedad;
  - sesión intensa;
  - valor aislado de HRV;
  - contexto a las 8:00.

## Limitaciones

- La adaptación necesita al menos 3 tests separados por 3 semanas o más; hasta entonces, la referencia manda.
- Las sesiones intensas para el aviso de recuperación se conocen después de abrir SPRING (se clasifican allí).
- Los rangos y escenarios no están calibrados con resultados reales del usuario.
- Los parámetros de la previa (0,10) y de la agregación (0,25) son supuestos documentados.
