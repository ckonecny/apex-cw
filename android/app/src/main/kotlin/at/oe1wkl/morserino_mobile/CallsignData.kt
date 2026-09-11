package at.oe1wkl.morserino_mobile

import kotlin.random.Random

/**
 * Real-world weighted callsign prefix table (973 entries) + generator, ported
 * from Software/src/Version 6 and newer/callsign_prefixes.h and getRandomCall()
 * in m32_v6.ino. Continent bitmask matches exactly: EU=0x01, NA=0x02, SA=0x04,
 * AF=0x08, AS=0x10, OC=0x20, AN=0x40. Weight is log-scaled frequency from real
 * callsign data (1=rare/theoretical, up to 255=very common). Table extracted by
 * script from the upstream header, not hand-typed.
 */
object CallsignData {
    const val CONT_EU = 0x01
    const val CONT_NA = 0x02
    const val CONT_SA = 0x04
    const val CONT_AF = 0x08
    const val CONT_AS = 0x10
    const val CONT_OC = 0x20
    const val CONT_AN = 0x40
    const val CONT_ALL = 0x7F

    data class Entry(val prefix: String, val continent: Int, val weight: Int)

    // "prefix:continentMask:weight;..."
    private const val ENCODED =
        "1A:1:1;1A0:1:1;1B:16:1;1M:32:1;1S:32:1;2A:1:1;2B:1:1;2C:1:1;2D:1:20;2E:1:136;2F:1:1;2G:1:1;2H:1:1;2I:1:40;2K:1:1;2L:1:1;2M:1:66;2N:1:1;2O:1:1;2P:1:1;2Q:1:1;2R:1:1;2S:1:1;2T:1:1;2U:1:1;2V:1:1;2X:1:1;2Y:1:1;2Z:1:1;3A:1:20;3B:8:1;3B6:8:1;3B7:8:20;3B8:8:46;3B9:8:20;3C:8:1;3C0:8:1;3D2:32:71;3D6:8:1;3DA:8:32;3DB:8:1;3DC:8:1;3DD:8:1;3DE:8:1;3DF:8:1;3DG:8:1;3DH:8:1;3DI:8:1;3DJ:8:1;3DK:8:1;3DL:8:1;3DM:8:1;3E:2:20;3F:2:20;3G:4:51;3H:16:1;3I:16:1;3J:16:1;3K:16:1;3L:16:1;3M:16:1;3N:16:1;3O:16:1;3P:16:1;3Q:16:1;3R:16:1;3S:16:1;3T:16:1;3U:16:1;3V:8:46;3W:16:40;3X:8:1;3Y:72:1;3Z:1:75;4A:2:63;4B:2:1;4C:2:20;4D:32:20;4E:32:60;4F:32:60;4G:32:66;4H:32:1;4I:32:66;4J:16:20;4J1:1:1;4K:16:56;4K1:4:20;4L:16:83;4N:1:1;4N5:1:1;4O:1:56;4P:16:1;4Q:16:1;4R:16:1;4S:16:32;4T:4:20;4U:1:63;4U_I:1:1;4W:32:1;4X:16:93;4X1:16:79;4Z:16:100;5A:8:1;5B:16:95;5C:8:1;5D:8:1;5E:8:1;5F:8:1;5G:8:1;5H:8:40;5H1:8:1;5I:8:1;5L:8:1;5M:8:1;5N:8:1;5O:8:1;5R:8:40;5S:8:1;5T:8:1;5U:8:1;5V:8:1;5W:32:40;5X:8:46;5Y:8:20;5Z:8:40;6A:8:1;6B:8:32;6C:16:1;6D:2:20;6E:2:1;6F:2:1;6G:2:1;6H:2:1;6I:2:1;6J:2:1;6K:16:60;6L:16:1;6M:16:20;6N:16:1;6O:8:20;6P:16:1;6Q:16:1;6R:16:1;6S:16:1;6T:8:1;6U:8:1;6V:8:1;6W:8:1;6X:8:1;6Z:8:1;7A:32:88;7B:32:75;7C:32:66;7D:32:46;7E:32:46;7F:32:20;7G:32:32;7H:32:46;7I:32:51;7J:16:20;7J1:16:32;7K:16:91;7L:16:86;7M:16:66;7N:16:75;7O:16:1;7P:8:1;7Q:8:63;7R:8:1;7T:8:1;7U:8:1;7V:8:1;7W:8:20;7X:8:51;7Y:8:1;7Z:16:71;8A:32:20;8B:32:1;8C:32:1;8D:32:1;8E:32:1;8F:32:1;8G:32:1;8H:32:20;8I:32:1;8J:16:56;8K:16:32;8L:16:1;8M:16:1;8N:16:60;8O:8:1;8Q:24:32;8R:4:40;8T:16:1;8U:16:1;8V:16:1;8W:16:1;8X:16:1;8Y:16:1;8Z:16:1;8Z4:16:1;8Z5:16:1;9A:1:163;9B:16:1;9C:16:1;9D:16:1;9E:8:1;9F:8:1;9G:8:32;9H:1:75;9I:8:1;9J:8:40;9K:16:73;9K3:16:1;9L:8:1;9M:16:1;9M0:32:1;9M2:16:106;9M4:16:1;9M6:32:79;9M8:32:51;9N:16:20;9O:8:1;9P:8:1;9Q:8:1;9R:8:1;9S:8:1;9S4:1:1;9T:8:1;9U:8:1;9U5:8:1;9V:16:60;9W:16:81;9X:8:1;9Y:4:51;9Z:4:46;A2:8:1;A3:32:20;A4:16:75;A5:16:1;A6:16:81;A7:16:66;A8:8:1;A9:16:20;AA:2:160;AB:2:143;AC:2:145;AC3:16:79;AC4:16:79;AD:2:137;AE:2:132;AF:2:124;AG:2:120;AH:2:75;AH8S:32:1;AI:2:133;AJ:2:111;AK:2:118;AP:16:40;AQ:16:1;AR:16:1;AS:16:1;AT:16:51;AU:16:1;AV:16:1;AW:16:1;AY:4:56;AZ:4:51;B0:16:20;B1:16:32;B2:16:1;B3:16:1;B4:16:46;B5:16:20;B6:16:1;B7:16:40;B8:16:1;B9:16:1;BA:16:118;BB:16:1;BC:16:1;BD:16:138;BE:16:1;BF:16:1;BG:16:145;BH:16:138;BI:16:130;BJ:16:1;BK:16:1;BL:16:1;BQ9:16:1;BR:16:1;BS:16:1;BS7:16:1;BT:16:1;BV:16:71;BV9:16:1;BY:16:105;BZ:16:1;C2:32:20;C3:1:56;C4:16:46;C5:8:40;C8:8:1;C9:24:1;CA:4:93;CB:4:95;CC:4:1;CD:4:63;CE:4:127;CE0:4:20;CE9:68:1;CF:2:1;CG:2:1;CH:2:1;CI:2:1;CJ:2:20;CK:2:32;CN:8:79;CN2:8:32;CP:4:32;CR8:48:1;CT:1:142;CT3:8:69;CU:1:73;CV:4:40;CW:4:56;CX:4:112;CY:2:1;CZ:2:1;D2:8:46;D3:8:1;D4:8:66;D5:8:1;D6:8:1;D7:16:1;D8:16:1;D9:16:32;DA:1:125;DB:1:125;DC:1:129;DD:1:121;DE:1:1;DF:1:166;DG:1:152;DH:1:136;DI:1:1;DJ:1:154;DK:1:176;DL:1:210;DM:1:156;DN:1:88;DO:1:158;DP:1:103;DQ:1:86;DR:1:117;DS:16:94;DT:16:1;DU:32:108;DV:32:87;DW:32:51;DX:32:91;DY:32:46;DZ:32:51;E2:16:99;E3:8:1;E4:16:1;E5:32:1;E6:32:20;E7:1:137;EA:1:193;EA6:1:102;EA8:8:127;EA9:8:56;EB:1:115;EC:1:117;ED:1:119;EE:1:96;EF:1:103;EG:1:69;EH:1:40;EI:1:139;EJ:1:1;EK:16:51;EL:8:20;EM:1:63;EN:1:20;EO:1:1;EP:16:20;EQ:16:1;ER:1:97;ES:1:137;ET:8:20;EU:1:110;EV:1:51;EW:1:120;EX:16:66;EY:16:60;EZ:16:1;F:1:204;FA:1:1;FB:1:1;FB8:8:1;FC:1:1;FD:1:1;FE:1:20;FF:8:32;FH:8:1;FI:1:1;FI8:16:1;FK:32:51;FL:1:1;FN:1:1;FN8:16:1;FO:32:32;FO0:32:1;FQ:1:1;FQ8:8:1;FR:8:40;FR/E:8:1;FR/G:8:1;FR/J:8:1;FR/T:8:1;FT:1:1;FT5W:8:1;FT5X:8:1;FT5Z:8:1;FU:1:1;FV:1:1;FW:32:40;FX:1:1;FY:4:32;FZ:1:1;G:1:197;GA:1:1;GB:1:1;GC:1:32;GD:1:46;GE:1:77;GF:1:20;GG:1:1;GH:1:20;GI:1:102;GJ:1:56;GK:1:1;GL:1:1;GM:1:138;GN:1:1;GO:1:1;GP:1:1;GQ:1:1;GR:1:20;GS:1:51;GT:1:32;GU:1:71;GV:1:1;GW:1:122;GX:1:86;GY:1:1;GZ:1:1;H2:16:20;H3:2:1;H4:32:20;H40:32:20;H5:8:1;H8:2:1;H9:2:20;HA:1:171;HB:1:170;HB0:1:71;HC:4:77;HC8:4:32;HD:4:20;HD8:4:40;HF:1:95;HF0:4:32;HG:1:128;HJ:4:71;HK:4:108;HK0:4:1;HL:16:113;HM:16:1;HN:16:1;HO:2:1;HP:2:79;HS:16:108;HV:1:20;HW:1:1;HX:1:1;HY:1:1;HZ:16:81;I:1:216;I1:1:98;I5:8:79;IM0:1:1;IS0:1:107;J2:8:1;J5:8:1;JA:16:184;JB:16:1;JC:16:1;JD:16:1;JD1:48:32;JE:16:145;JF:16:139;JG:16:133;JH:16:165;JI:16:126;JJ:16:136;JK:16:137;JL:16:122;JM:16:122;JN:16:110;JO:16:111;JP:16:105;JQ:16:110;JR:16:150;JR6:16:84;JS:16:107;JT:16:60;JU:16:20;JV:16:1;JW:1:40;JX:1:1;JY:16:20;JZ:32:1;JZ0:32:1;K:2:255;KC4:64:115;KH0:32:20;KH1:32:1;KH2:32:46;KH3:32:1;KH4:32:1;KH5:32:1;KH5K:32:1;KH6:32:99;KH7:32:63;KH7K:32:1;KH8:32:1;KH8S:32:1;KH9:32:1;KP1:2:1;KR6:16:46;KR8:16:46;L2:4:20;L3:4:32;L4:4:1;L5:4:1;L6:4:1;L7:4:51;L8:4:1;L9:4:1;LA:1:139;LB:1:109;LC:1:105;LD:1:1;LE:1:1;LF:1:1;LG:1:20;LH:1:1;LI:1:1;LJ:1:1;LK:1:1;LL:1:1;LM:1:1;LN:1:75;LO:4:32;LP:4:40;LQ:4:56;LR:4:32;LS:4:51;LT:4:88;LU:4:146;LV:4:63;LW:4:94;LX:1:95;LY:1:144;LZ:1:165;M:1:185;M2:1:73;M4:1:69;MA:1:1;MB:1:1;MD:1:51;ME:1:63;MF:1:1;MG:1:1;MH:1:1;MI:1:100;MK:1:1;ML:1:1;MM:1:122;MN:1:1;MO:1:1;MP:1:20;MQ:1:1;MR:1:1;MS:1:20;MT:1:1;MU:1:46;MV:1:1;MX:1:71;MY:1:1;MZ:1:1;N:2:232;NH8S:32:1;NP1:2:1;OA:4:77;OB:4:1;OC:4:1;OD:16:51;OE:1:159;OF:1:1;OG:1:112;OH:1:166;OH0:1:73;OH0M:1:20;OI:1:40;OJ0:1:20;OK:1:183;OL:1:120;OM:1:158;ON:1:173;OO:1:71;OP:1:84;OQ:1:71;OR:1:100;OS:1:63;OT:1:105;OY:1:51;OZ:1:141;P2:32:1;P3:16:71;P4:4:73;P5:16:1;P6:16:1;P7:16:1;P8:16:1;P9:16:1;PA:1:174;PB:1:86;PC:1:110;PD:1:154;PE:1:134;PF:1:77;PG:1:87;PH:1:83;PI:1:114;PJ2:4:60;PJ4:4:71;PJ5:2:32;PJ6:2:32;PJ7:4:46;PJ8:2:1;PJ9:4:1;PK:32:1;PK1:32:1;PK2:32:1;PK3:32:1;PK4:32:1;PK5:32:1;PK6:32:1;PL:32:1;PM:32:1;PN:32:1;PO:32:1;PP:4:137;PP0F:4:1;PP0S:4:1;PP0T:4:1;PQ:4:60;PR:4:105;PS:4:91;PT:4:122;PU:4:155;PV:4:91;PW:4:90;PX:4:88;PY:4:181;PZ:4:51;R1FJ:1:1;R1MV:1:1;RA:17:161;RB:17:1;RC:17:123;RD:17:114;RE:17:1;RF:17:40;RG:17:92;RH:17:1;RI:17:1;RJ:17:69;RK:17:131;RL:17:107;RM:17:112;RM1V:1:1;RN:17:129;RO:17:91;RP:17:1;RQ:17:79;RR:17:1;RS:17:1;RT:17:119;RU:17:129;RV:17:119;RW:17:136;RX:17:114;RY:17:101;RZ:17:122;S0:8:32;S2:16:51;S3:16:1;S4:8:1;S5:1:167;S6:16:1;S7:8:32;S8:8:1;S9:8:1;SA:1:99;SB:1:63;SC:1:51;SD:1:75;SE:1:99;SF:1:69;SG:1:79;SH:1:20;SI:1:51;SJ:1:56;SK:1:92;SL:1:1;SM:1:146;SN:1:136;SO:1:113;SP:1:191;SQ:1:162;SR:1:1;SSA:8:1;SSB:8:1;SSC:8:1;SSD:8:1;SSE:8:1;SSF:8:1;SSG:8:1;SSH:8:1;SSI:8:1;SSJ:8:1;SSK:8:1;SSL:8:1;SSM:8:1;SSN:8:1;SSO:8:1;SSP:8:1;SSQ:8:1;SSR:8:1;SSS:8:1;SST:8:1;SSU:8:1;SSV:8:1;SSW:8:1;SSX:8:1;SSY:8:1;SSZ:8:1;ST:8:1;ST0:8:1;SU:8:40;SV:1:152;SV/A:1:1;SV5:1:69;SV9:1:81;SW:1:20;SX:1:81;SY:1:66;SZ:1:69;T2:32:1;T30:32:20;T31:32:1;T32:32:20;T33:32:1;T5:8:1;T7:1:56;T8:32:51;T9:1:1;TA:17:136;TB:17:20;TC:17:83;TF:1:86;TH:1:1;TJ:8:1;TK:1:73;TL:8:20;TM:1:137;TN:8:1;TO:1:83;TP:1:20;TQ:1:1;TR:8:20;TT:8:20;TU:8:1;TV:1:1;TW:1:1;TX:32:1;TY:8:32;TZ:8:20;UA2:1:56;UJ:16:1;UK:16:60;UL:16:1;UM:16:1;UN:16:116;UN1:1:20;UO:16:20;UP:16:66;UQ:16:1;UR:1:137;US:1:117;UT:1:139;UU:1:1;UV:1:46;UW:1:100;UX:1:96;UY:1:91;UZ:1:81;V5:8:63;V6:32:32;V7:32:32;V8:32:51;V9:8:1;VA:2:167;VB:2:32;VC:2:81;VD:2:1;VE:2:193;VF:2:20;VG:2:1;VK:32:156;VK0:40:1;VK9:32:32;VK9C:32:20;VK9L:32:1;VK9M:32:1;VK9N:32:1;VK9W:32:1;VK9X:32:1;VO:2:100;VP:1:91;VP6:32:20;VP8:4:46;VQ:1:32;VQ1:8:1;VQ6:8:1;VQ9:8:1;VR:16:87;VS:1:1;VS2:48:1;VS4:32:1;VS9A:16:1;VS9H:16:1;VS9K:16:1;VS9P:16:1;VS9S:16:1;VT:16:1;VU:16:124;VV:16:1;VW:16:1;VX:2:20;VY:2:100;W:2:243;WH8S:32:1;WP1:2:1;XA:2:1;XB:2:1;XC:2:1;XD:2:1;XE:2:124;XF:2:20;XG:2:1;XH:2:1;XI:2:1;XJ:2:1;XK:2:1;XL:2:40;XM:2:1;XN:2:1;XO:2:20;XQ:4:77;XR:4:56;XS:16:1;XT:8:1;XU:16:32;XV:16:1;XV9:32:63;XW:16:32;XX9:16:32;XY:16:1;XZ:16:1;Y2:1:1;Y3:1:1;Y4:1:1;Y5:1:1;Y6:1:1;Y7:1:1;Y8:1:1;Y9:1:1;YA:16:1;YB:32:170;YC:32:172;YD:32:162;YE:32:118;YF:32:134;YG:32:138;YH:32:1;YI:16:20;YJ:32:32;YK:16:1;YL:1:129;YM:16:79;YO:1:168;YP:1:79;YQ:1:63;YR:1:88;YT:1:143;YU:1:148;YV:4:96;YW:4:32;YX:4:1;YY:4:63;YZ:1:1;Z2:8:1;Z3:1:105;Z6:1:69;Z8:8:1;ZA:1:63;ZB:1:20;ZB2:1:40;ZC4:16:32;ZC5:32:1;ZC6:16:1;ZD:1:1;ZD4:8:1;ZD7:8:51;ZD8:8:1;ZD9:8:20;ZE:1:1;ZG:1:1;ZH:1:1;ZI:1:1;ZJ:1:1;ZK:32:1;ZK1:32:1;ZK2:32:1;ZK3:32:1;ZL:32:120;ZL7:32:32;ZL8:32:1;ZL9:32:1;ZM:32:56;ZN:1:1;ZO:1:1;ZP:4:87;ZQ:1:1;ZR:8:32;ZS:8:102;ZS0:8:1;ZS8:8:1;ZS9:8:20;ZT:8:1;ZU:8:1;ZV:4:90;ZW:4:86;ZX:4:66;ZY:4:87;ZZ:4:91"

    val prefixes: List<Entry> by lazy {
        ENCODED.split(';').map {
            val parts = it.split(':')
            Entry(parts[0], parts[1].toInt(), parts[2].toInt())
        }
    }

    // Map preference value (0-6) to continent bitmask — matches getContinentMask().
    private fun continentMask(prefValue: Int): Int {
        val masks = intArrayOf(CONT_ALL, CONT_EU, CONT_NA, CONT_SA, CONT_AF, CONT_AS, CONT_OC)
        return if (prefValue in 0..6) masks[prefValue] else CONT_ALL
    }

    /**
     * Mirrors getRandomCall(maxLength) exactly (two-pass weighted selection over the
     * real prefix table, VK/ZL special-case generator, digit/suffix logic).
     * lengthOpt: 0=Unlimited, 1="3" chars, 2="4", 3="5", 4="6" (M32 "Length Calls" option values)
     * regionOpt: 0=All,1=EU,2=NA,3=SA,4=AF,5=AS,6=OC,7=VK/ZL (M32 "Calls Region" option values)
     * commonOnly: M32 "Call Prefixes" = Common only (weight >= 81 threshold)
     */
    fun randomCallsign(lengthOpt: Int, regionOpt: Int, commonOnly: Boolean): String {
        // "max 3 chars" only exists for a handful of NA/EU prefixes, so region is
        // ignored in that case (matches the real device's documented behavior).
        val vkzlOnly = regionOpt == 7 && lengthOpt != 1
        if (vkzlOnly) return randomVkZl()

        val contMask = if (lengthOpt != 1) continentMask(regionOpt) else CONT_ALL
        val minWeight = if (commonOnly) 81 else 0
        val maxPfxLen = if (lengthOpt > 0) lengthOpt else 99

        val matching = prefixes.filter {
            (it.continent and contMask) != 0 && it.weight >= minWeight && it.prefix.length <= maxPfxLen
        }
        val chosen = weightedPick(matching) ?: return randomFallbackCall()

        val sb = StringBuilder(chosen.prefix.uppercase())
        val endsWithDigit = sb.isNotEmpty() && sb.last().isDigit()
        if (!endsWithDigit || sb.length <= 2) sb.append('0' + Random.nextInt(10))

        val maxTotal = when {
            lengthOpt == 0 -> 10
            lengthOpt > 4  -> 6
            else           -> lengthOpt + 2
        }
        val suffixSpace = (maxTotal - sb.length).coerceIn(1, 3)

        val suffLen = if (lengthOpt == 0) {
            var s = Random.nextInt(1, 4)
            if (s == 1 && Random.nextInt(3) != 0) s = Random.nextInt(2, 4)
            s
        } else suffixSpace
        repeat(suffLen) { sb.append('A' + Random.nextInt(26)) }

        // Rare /P or /M suffix, unlimited length mode only (~12.5% chance).
        if (lengthOpt == 0 && Random.nextInt(8) == 0) {
            sb.append('/').append(if (Random.nextBoolean()) 'M' else 'P')
        }
        return sb.toString()
    }

    private fun weightedPick(list: List<Entry>): Entry? {
        val total = list.sumOf { it.weight }
        if (total <= 0) return null
        var pick = Random.nextInt(total)
        for (e in list) {
            pick -= e.weight
            if (pick < 0) return e
        }
        return list.last()
    }

    private fun randomFallbackCall(): String {
        val sb = StringBuilder()
        sb.append('A' + Random.nextInt(26))
        sb.append(Random.nextInt(10))
        repeat(3) { sb.append('A' + Random.nextInt(26)) }
        return sb.toString()
    }

    // 85% VK / 15% ZL, area-weighted, matching the real device's custom generator
    // (used only for "3 character calls" region-agnostic path AND explicit VK/ZL region).
    private fun randomVkZl(): String {
        val isVK = Random.nextInt(100) < 85
        val sb = StringBuilder()
        val area: Int
        if (isVK) {
            val r = Random.nextInt(100)
            area = when {
                r < 1 -> 0; r < 11 -> 1; r < 31 -> 2; r < 51 -> 3; r < 66 -> 4
                r < 76 -> 5; r < 81 -> 6; r < 96 -> 7; r < 99 -> 8; else -> 9
            }
            sb.append("VK")
        } else {
            val r = Random.nextInt(100)
            area = when { r < 35 -> 1; r < 70 -> 2; r < 90 -> 3; else -> 4 }
            sb.append("ZL")
        }
        sb.append(area)
        val suffixLen = if (Random.nextInt(10) < 3) 2 else 3
        repeat(suffixLen) { sb.append('A' + Random.nextInt(26)) }
        return sb.toString()
    }
}
