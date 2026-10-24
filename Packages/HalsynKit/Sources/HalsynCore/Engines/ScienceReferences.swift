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
    public static let trainingLoad = ScienceReference(
        citation: "Gabbett TJ. The training—injury prevention paradox: should athletes be training smarter and harder? Br J Sports Med. 2016;50(5):273–280.",
        url: "https://doi.org/10.1136/bjsports-2015-095788"
    )
}
