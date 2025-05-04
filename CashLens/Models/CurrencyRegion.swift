import Foundation
import SwiftUI

enum CurrencyRegion: String, CaseIterable {
    case all = "All"
    case americas = "Americas"
    case europe = "Europe"
    case asia = "Asia"
    case africa = "Africa"
    case oceania = "Oceania"
    case middleEast = "Middle East"
    
    var currencies: [Expense.Currency] {
        switch self {
        case .all:
            return Expense.Currency.allCases
        case .americas:
            return [
                .usd, .cad, .mxn, .brl, .ars, .clp, .cop, .pen, .uyu, .ves, .bob, .crc, .gtq, .hnl, .nio, .svc,
                .bzd, .jmd, .ttd, .bmd, .kyd, .ang, .awg, .bsd, .cup, .dop, .htg, .pab, .pyg, .gyd, .srd,
                .bbd
            ]
        case .europe:
            return [
                .eur, .gbp, .chf, .sek, .nok, .dkk, .pln, .ron, .czk, .huf, .bgn, .hrk, .rsd, .isk,
                .bam, .all, .mkd, .mdl, .gel, .amd, .azn, .byn, .imp, .jep, .ggp, .gip,
                .fkp
            ]
        case .asia:
            return [
                .jpy, .cny, .sgd, .hkd, .krw, .twd, .thb, .myr, .idr, .php, .vnd, .pkr, .bdt, .npr, .lkr, .mvr,
                .mmk, .khr, .lak, .mnt, .tjs, .tmt, .uzs, .kgs, .afn, .inr,
                .bnd, .mop
            ]
        case .africa:
            return [
                .zar, .egp, .ngn, .kes, .ghs, .mad, .dzd, .tnd, .lyd, .sdg, .etb, .ugx, .tzs, .mur,
                .bif, .cdf, .djf, .eri, .rwf, .sos, .ssp, .szl, .zmw, .zwl, .nad, .mwk, .mga, .scr,
                .kmf, .stn, .cve, .gmd, .gnf, .lrd, .sll, .mro, .mru, .shp, .aoa
            ]
        case .oceania:
            return [
                .aud, .nzd, .fjd, .pgk, .sbd, .top, .vuv, .wst, .xpf,
                .xcd
            ]
        case .middleEast:
            return [
                .aed, .sar, .ils, .qar, .kwd, .bhd, .omr, .jod, .lbp,
                .irr, .iqd, .syp, .yer
            ]
        }
    }
} 