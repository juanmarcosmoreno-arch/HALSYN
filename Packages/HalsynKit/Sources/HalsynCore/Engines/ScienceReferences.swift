import Foundation

/// Publicación citada por un cálculo, con enlace a la fuente.
public struct ScienceReference: Hashable, Identifiable, Sendable {
    public let citation: String
    public let url: URL

    public var id: String { citation }

    init(citation: String, url: String) {
        self.citation = citation
        self.url = URL(string: url)!
    }
}

/// Referencias que usan los cálculos de HÅLSYN (ver Documentation/SCIENTIFIC_REFERENCES.md).
public enum ScienceReferences {
    public static let lifesEssential8 = ScienceReference(
        citation: "Lloyd-Jones DM, et al. Life's Essential 8: Updating and Enhancing the American Heart Association's Construct of Cardiovascular Health. Circulation. 2022;146(5):e18–e43.",
        url: "https://doi.org/10.1161/CIR.0000000000001078"
    )
    public static let mepa = ScienceReference(
        citation: "Cerwinske LA, Rasmussen HE, Volgman AS, Tangney CC. Evaluation of a dietary screener: the Mediterranean Eating Pattern for Americans tool. J Hum Nutr Diet. 2017;30(5):596–603.",
        url: "https://doi.org/10.1111/jhn.12451"
    )
    public static let danielsVDOT = ScienceReference(
        citation: "Daniels J, Gilbert J. Oxygen Power: Performance Tables for Distance Runners. 1979; Daniels J. Daniels' Running Formula. Human Kinetics.",
        url: "https://search.worldcat.org/search?q=Daniels%27+Running+Formula"
    )
    public static let gradedTraining = ScienceReference(
        citation: "Buist I, et al. No effect of a graded training program on the number of running-related injuries in novice runners: a randomized controlled trial. Am J Sports Med. 2008;36(1):33–39.",
        url: "https://doi.org/10.1177/0363546507307505"
    )
    public static let weeklyProgression = ScienceReference(
        citation: "Nielsen RO, et al. Excessive progression in weekly running distance and risk of running-related injuries: an association which varies according to type of injury. J Orthop Sports Phys Ther. 2014;44(10):739–747.",
        url: "https://doi.org/10.2519/jospt.2014.5164"
    )
    public static let taper = ScienceReference(
        citation: "Bosquet L, Montpetit J, Arvisais D, Mujika I. Effects of tapering on performance: a meta-analysis. Med Sci Sports Exerc. 2007;39(8):1358–1365.",
        url: "https://doi.org/10.1249/mss.0b013e31806010e0"
    )
    public static let sleepRegularityMortality = ScienceReference(
        citation: "Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration: a prospective cohort study. Sleep. 2024;47(1):zsad253.",
        url: "https://doi.org/10.1093/sleep/zsad253"
    )
    public static let sleepRegularityIndex = ScienceReference(
        citation: "Phillips AJK, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. Sci Rep. 2017;7:3216.",
        url: "https://doi.org/10.1038/s41598-017-03171-4"
    )
    public static let dailySteps = ScienceReference(
        citation: "Paluch AE, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health. 2022;7(3):e219–e228.",
        url: "https://doi.org/10.1016/S2468-2667(21)00302-9"
    )
    public static let sleepDuration = ScienceReference(
        citation: "Watson NF, et al. Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep Medicine and Sleep Research Society. Sleep. 2015;38(6):843–844.",
        url: "https://doi.org/10.5665/sleep.4716"
    )
    public static let physicalActivity = ScienceReference(
        citation: "Bull FC, et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med. 2020;54(24):1451–1462.",
        url: "https://doi.org/10.1136/bjsports-2020-102955"
    )
    // CYKEL
    public static let powerMeterTraining = ScienceReference(
        citation: "Allen H, Coggan AR, McGregor S. Training and Racing with a Power Meter. 3rd ed. Boulder (CO): VeloPress; 2019.",
        url: "https://search.worldcat.org/isbn/9781937715939"
    )
    public static let powerLevels = ScienceReference(
        citation: "Coggan AR. Power training levels. TrainingPeaks.",
        url: "https://www.trainingpeaks.com/learn/articles/power-training-levels/"
    )
    public static let ftpVersusMLSS = ScienceReference(
        citation: "Borszcz FK, Tramontin AF, Costa VP. Is the functional threshold power interchangeable with the maximal lactate steady state in trained cyclists? Int J Sports Physiol Perform. 2019;14(8):1029–1035.",
        url: "https://doi.org/10.1123/ijspp.2018-0572"
    )
    public static let ftpRecreational = ScienceReference(
        citation: "Valenzuela PL, Morales JS, Foster C, Lucia A, de la Villa P. Is the functional threshold power a valid surrogate of the lactate threshold? Int J Sports Physiol Perform. 2018;13(10):1293–1298.",
        url: "https://doi.org/10.1123/ijspp.2018-0008"
    )
    public static let heartRateTransfer = ScienceReference(
        citation: "Roecker K, Striegel H, Dickhuth HH. Heart-rate recommendations: transfer between running and cycling exercise? Int J Sports Med. 2003;24(3):173–178.",
        url: "https://doi.org/10.1055/s-2003-39087"
    )
    public static let activeCommuting = ScienceReference(
        citation: "Celis-Morales CA, et al. Association between active commuting and incident cardiovascular disease, cancer, and mortality: prospective cohort study. BMJ. 2017;357:j1456.",
        url: "https://doi.org/10.1136/bmj.j1456"
    )

    // Carga de entrenamiento
    public static let banisterTRIMP = ScienceReference(
        citation: "Morton RH, Fitz-Clarke JR, Banister EW. Modeling human performance in running. J Appl Physiol. 1990;69(3):1171–1177.",
        url: "https://doi.org/10.1152/jappl.1990.69.3.1171"
    )
    public static let fitnessFatigueModel = ScienceReference(
        citation: "Calvert TW, Banister EW, Savage MV, Bach T. A systems model of the effects of training on physical performance. IEEE Trans Syst Man Cybern. 1976;SMC-6(2):94–102.",
        url: "https://doi.org/10.1109/TSMC.1976.5409179"
    )
    public static let workloadRatioPitfalls = ScienceReference(
        citation: "Impellizzeri FM, Tenan MS, Kempton T, Novak A, Coutts AJ. Acute:Chronic Workload Ratio: Conceptual Issues and Fundamental Pitfalls. Int J Sports Physiol Perform. 2020;15(6):907–913.",
        url: "https://doi.org/10.1123/ijspp.2019-0864"
    )

    public static let trainingLoad = ScienceReference(
        citation: "Gabbett TJ. The training—injury prevention paradox: should athletes be training smarter and harder? Br J Sports Med. 2016;50(5):273–280.",
        url: "https://doi.org/10.1136/bjsports-2015-095788"
    )
}
