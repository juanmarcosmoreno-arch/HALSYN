import Foundation

/// Tablas de referencia incluidas en la app. Solo datos copiados de la fuente
/// publicada, con su cita (Documentation/SCIENTIFIC_REFERENCES.md); nunca
/// estimaciones. Generado a partir de las tablas verificadas: no editar a mano.
public enum ReferenceLibrary {
    public static let datasets: [ReferenceDataset] = [vo2Max, restingHeartRate]

    /// FRIEND 2015, tabla 3 (cinta, V̇O₂máx medido). La actualización de 2022 da
    /// valores 1,5–4,6 mL·kg⁻¹·min⁻¹ más bajos; su tabla no se pudo verificar todavía.
    public static let vo2Max = ReferenceDataset(
        id: "friend-2015-treadmill",
        metric: .vo2Max,
        citation: "Kaminsky LA, Arena R, Myers J. Reference Standards for Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise Testing: Data From the Fitness Registry and the Importance of Exercise National Database. Mayo Clin Proc. 2015;90(11):1515–1523.",
        url: "https://doi.org/10.1016/j.mayocp.2015.07.026",
        population: "7.783 pruebas en 8 laboratorios de EE. UU. (2014–2015), adultos de 20 a 79 años sin enfermedad cardiovascular ni EPOC conocidas.",
        method: "Prueba de esfuerzo máxima en cinta con análisis de gases (V̇O₂máx medido).",
        caveats: [
            "El VO₂ máx. del Apple Watch es una estimación submáxima; la tabla se obtuvo con pruebas de laboratorio.",
            "Muestra de conveniencia de EE. UU.; poblaciones nórdicas suelen tener valores más altos.",
            "Tabla de 2015; la actualización de 2022 da valores algo más bajos (te situaría un poco más arriba).",
            "Sin datos para 80 años o más.",
        ],
        higherIsBetter: true,
        rows: [
            ReferenceRow(sex: .male, ageRange: 20...29, sampleSize: 513, percentiles: [5.0: 29.0, 10.0: 32.1, 25.0: 40.1, 50.0: 48.0, 75.0: 55.2, 90.0: 61.8, 95.0: 66.3]),
            ReferenceRow(sex: .male, ageRange: 30...39, sampleSize: 963, percentiles: [5.0: 27.2, 10.0: 30.2, 25.0: 35.9, 50.0: 42.4, 75.0: 49.2, 90.0: 56.5, 95.0: 59.8]),
            ReferenceRow(sex: .male, ageRange: 40...49, sampleSize: 1327, percentiles: [5.0: 24.2, 10.0: 26.8, 25.0: 31.9, 50.0: 37.8, 75.0: 45.0, 90.0: 52.1, 95.0: 55.6]),
            ReferenceRow(sex: .male, ageRange: 50...59, sampleSize: 1078, percentiles: [5.0: 20.9, 10.0: 22.8, 25.0: 27.1, 50.0: 32.6, 75.0: 39.7, 90.0: 45.6, 95.0: 50.7]),
            ReferenceRow(sex: .male, ageRange: 60...69, sampleSize: 593, percentiles: [5.0: 17.4, 10.0: 19.8, 25.0: 23.7, 50.0: 28.2, 75.0: 34.5, 90.0: 40.3, 95.0: 43.0]),
            ReferenceRow(sex: .male, ageRange: 70...79, sampleSize: 137, percentiles: [5.0: 16.3, 10.0: 17.1, 25.0: 20.4, 50.0: 24.4, 75.0: 30.4, 90.0: 36.6, 95.0: 39.7]),
            ReferenceRow(sex: .female, ageRange: 20...29, sampleSize: 410, percentiles: [5.0: 21.7, 10.0: 23.9, 25.0: 30.5, 50.0: 37.6, 75.0: 44.7, 90.0: 51.3, 95.0: 56.0]),
            ReferenceRow(sex: .female, ageRange: 30...39, sampleSize: 608, percentiles: [5.0: 19.0, 10.0: 20.9, 25.0: 25.3, 50.0: 30.2, 75.0: 36.1, 90.0: 41.4, 95.0: 45.8]),
            ReferenceRow(sex: .female, ageRange: 40...49, sampleSize: 843, percentiles: [5.0: 17.0, 10.0: 18.8, 25.0: 22.1, 50.0: 26.7, 75.0: 32.4, 90.0: 38.4, 95.0: 41.7]),
            ReferenceRow(sex: .female, ageRange: 50...59, sampleSize: 805, percentiles: [5.0: 16.0, 10.0: 17.3, 25.0: 19.9, 50.0: 23.4, 75.0: 27.6, 90.0: 32.0, 95.0: 35.9]),
            ReferenceRow(sex: .female, ageRange: 60...69, sampleSize: 408, percentiles: [5.0: 13.4, 10.0: 14.6, 25.0: 17.2, 50.0: 20.0, 75.0: 23.8, 90.0: 27.0, 95.0: 29.4]),
            ReferenceRow(sex: .female, ageRange: 70...79, sampleSize: 98, percentiles: [5.0: 13.1, 10.0: 13.6, 25.0: 15.6, 50.0: 18.3, 75.0: 20.8, 90.0: 23.1, 95.0: 24.1]),
        ]
    )

    /// NHANES 1999–2008 (Ostchega et al., NHSR n.º 41, 2011), tablas 2 y 3. Dominio público.
    public static let restingHeartRate = ReferenceDataset(
        id: "nhanes-1999-2008-pulse",
        metric: .restingHeartRate,
        citation: "Ostchega Y, Porter KS, Hughes J, Dillon CF, Nwankwo T. Resting pulse rate reference data for children, adolescents, and adults: United States, 1999–2008. National Health Statistics Reports no. 41. NCHS; 2011.",
        url: "https://www.cdc.gov/nchs/data/nhsr/nhsr041.pdf",
        population: "Muestra representativa de EE. UU. (NHANES 1999–2008), 14.200 adultos; excluye embarazo, infección probable, pulso irregular, tiroides alterada y fármacos que cambian la frecuencia cardíaca (p. ej., betabloqueantes).",
        method: "Pulso radial contado a mano 30 s (×2), sentado tras unos 4 minutos de reposo; una sola medición por persona.",
        caveats: [
            "La FC en reposo del Apple Watch se calcula de otra forma (lecturas ópticas en reposo a lo largo del día).",
            "Datos de EE. UU. de 1999–2008.",
            "Si tomas fármacos que cambian la frecuencia cardíaca, esta comparación no se aplica.",
        ],
        higherIsBetter: false,
        rows: [
            ReferenceRow(sex: .male, ageRange: 20...39, sampleSize: 3445, percentiles: [1.0: 47.0, 2.5: 50.0, 5.0: 52.0, 10.0: 55.0, 25.0: 61.0, 50.0: 69.0, 75.0: 76.0, 90.0: 84.0, 95.0: 89.0, 97.5: 95.0, 99.0: 101.0]),
            ReferenceRow(sex: .male, ageRange: 40...59, sampleSize: 2559, percentiles: [1.0: 46.0, 2.5: 49.0, 5.0: 52.0, 10.0: 55.0, 25.0: 61.0, 50.0: 68.0, 75.0: 77.0, 90.0: 85.0, 95.0: 90.0, 97.5: 95.0, 99.0: 104.0]),
            ReferenceRow(sex: .male, ageRange: 60...79, sampleSize: 1147, percentiles: [1.0: 45.0, 2.5: 48.0, 5.0: 50.0, 10.0: 54.0, 25.0: 60.0, 50.0: 67.0, 75.0: 75.0, 90.0: 84.0, 95.0: 91.0, 97.5: 98.0, 99.0: 102.0]),
            ReferenceRow(sex: .male, ageRange: 80...120, sampleSize: 197, percentiles: [2.5: 48.0, 5.0: 51.0, 10.0: 54.0, 25.0: 61.0, 50.0: 68.0, 75.0: 78.0, 90.0: 86.0, 95.0: 94.0, 97.5: 97.0]),
            ReferenceRow(sex: .female, ageRange: 20...39, sampleSize: 3061, percentiles: [1.0: 52.0, 2.5: 55.0, 5.0: 57.0, 10.0: 60.0, 25.0: 66.0, 50.0: 74.0, 75.0: 82.0, 90.0: 89.0, 95.0: 95.0, 97.5: 99.0, 99.0: 104.0]),
            ReferenceRow(sex: .female, ageRange: 40...59, sampleSize: 2409, percentiles: [1.0: 51.0, 2.5: 53.0, 5.0: 56.0, 10.0: 59.0, 25.0: 64.0, 50.0: 71.0, 75.0: 79.0, 90.0: 86.0, 95.0: 92.0, 97.5: 97.0, 99.0: 101.0]),
            ReferenceRow(sex: .female, ageRange: 60...79, sampleSize: 1163, percentiles: [1.0: 52.0, 2.5: 54.0, 5.0: 56.0, 10.0: 59.0, 25.0: 64.0, 50.0: 70.0, 75.0: 78.0, 90.0: 86.0, 95.0: 92.0, 97.5: 96.0, 99.0: 102.0]),
            ReferenceRow(sex: .female, ageRange: 80...120, sampleSize: 219, percentiles: [2.5: 53.0, 5.0: 56.0, 10.0: 59.0, 25.0: 64.0, 50.0: 71.0, 75.0: 77.0, 90.0: 85.0, 95.0: 93.0, 97.5: 98.0, 99.0: 100.0]),
        ]
    )
}
