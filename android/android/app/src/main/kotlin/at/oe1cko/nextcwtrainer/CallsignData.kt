package at.oe1cko.nextcwtrainer

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

    data class Entry(val prefix: String, val continent: Int, val weight: Int, val cqZone: Int)

    /** A generated call plus what getRandomCall() leaves in lastGeneratedCallContinent/-CqZone. */
    data class CallInfo(val call: String, val continent: Int, val cqZone: Int)

    // "prefix:continentMask:weight:cqZone;..."
    private const val ENCODED =
        "1A:1:1:15;1A0:1:1:15;1B:16:1:20;1M:32:1:32;1S:32:1:26;2A:1:1:14;2B:1:1:14;2C:1:1:14;2D:1:20:14;2E:1:136:14;2F:1:1:14;2G:1:1:14;2H:1:1:14;2I:1:40:14;2K:1:1:14;2L:1:1:14;2M:1:66:14;2N:1:1:14;2O:1:1:14;2P:1:1:14;2Q:1:1:14;2R:1:1:14;2S:1:1:14;2T:1:1:14;2U:1:1:14;2V:1:1:14;2X:1:1:14;2Y:1:1:14;2Z:1:1:14;3A:1:20:14;3B:8:1:39;3B6:8:1:39;3B7:8:20:39;3B8:8:46:39;3B9:8:20:39;3C:8:1:36;3C0:8:1:36;3D2:32:71:32;3D6:8:1:38;3DA:8:32:38;3DB:8:1:38;3DC:8:1:38;3DD:8:1:38;3DE:8:1:38;3DF:8:1:38;3DG:8:1:38;3DH:8:1:38;3DI:8:1:38;3DJ:8:1:38;3DK:8:1:38;3DL:8:1:38;3DM:8:1:38;3E:2:20:7;3F:2:20:7;3G:4:51:12;3H:16:1:24;3I:16:1:24;3J:16:1:24;3K:16:1:24;3L:16:1:24;3M:16:1:24;3N:16:1:24;3O:16:1:24;3P:16:1:24;3Q:16:1:24;3R:16:1:24;3S:16:1:24;3T:16:1:24;3U:16:1:24;3V:8:46:33;3W:16:40:26;3X:8:1:35;3Y:72:1:12;3Z:1:75:15;4A:2:63:6;4B:2:1:6;4C:2:20:6;4D:32:20:27;4E:32:60:27;4F:32:60:27;4G:32:66:27;4H:32:1:27;4I:32:66:27;4J:16:20:21;4J1:1:1:16;4K:16:56:21;4K1:4:20:13;4L:16:83:21;4N:1:1:15;4N5:1:1:15;4O:1:56:15;4P:16:1:22;4Q:16:1:22;4R:16:1:22;4S:16:32:22;4T:4:20:10;4U:1:63:14;4U_I:1:1:14;4W:32:1:28;4X:16:93:20;4X1:16:79:20;4Z:16:100:20;5A:8:1:34;5B:16:95:20;5C:8:1:33;5D:8:1:33;5E:8:1:33;5F:8:1:33;5G:8:1:33;5H:8:40:37;5H1:8:1:37;5I:8:1:37;5L:8:1:35;5M:8:1:35;5N:8:1:35;5O:8:1:35;5R:8:40:39;5S:8:1:39;5T:8:1:35;5U:8:1:35;5V:8:1:35;5W:32:40:32;5X:8:46:37;5Y:8:20:37;5Z:8:40:37;6A:8:1:34;6B:8:32:34;6C:16:1:20;6D:2:20:6;6E:2:1:6;6F:2:1:6;6G:2:1:6;6H:2:1:6;6I:2:1:6;6J:2:1:6;6K:16:60:25;6L:16:1:25;6M:16:20:25;6N:16:1:25;6O:8:20:37;6P:16:1:21;6Q:16:1:21;6R:16:1:21;6S:16:1:21;6T:8:1:34;6U:8:1:34;6V:8:1:35;6W:8:1:35;6X:8:1:39;6Z:8:1:35;7A:32:88:28;7B:32:75:28;7C:32:66:28;7D:32:46:28;7E:32:46:28;7F:32:20:28;7G:32:32:28;7H:32:46:28;7I:32:51:28;7J:16:20:25;7J1:16:32:27;7K:16:91:25;7L:16:86:25;7M:16:66:25;7N:16:75:25;7O:16:1:21;7P:8:1:37;7Q:8:63:37;7R:8:1:33;7T:8:1:33;7U:8:1:33;7V:8:1:33;7W:8:20:33;7X:8:51:33;7Y:8:1:33;7Z:16:71:21;8A:32:20:28;8B:32:1:28;8C:32:1:28;8D:32:1:28;8E:32:1:28;8F:32:1:28;8G:32:1:28;8H:32:20:28;8I:32:1:28;8J:16:56:25;8K:16:32:25;8L:16:1:25;8M:16:1:25;8N:16:60:25;8O:8:1:38;8Q:24:32:22;8R:4:40:9;8T:16:1:22;8U:16:1:22;8V:16:1:22;8W:16:1:22;8X:16:1:22;8Y:16:1:22;8Z:16:1:21;8Z4:16:1:21;8Z5:16:1:21;9A:1:163:15;9B:16:1:21;9C:16:1:21;9D:16:1:21;9E:8:1:37;9F:8:1:37;9G:8:32:35;9H:1:75:15;9I:8:1:36;9J:8:40:36;9K:16:73:21;9K3:16:1:21;9L:8:1:35;9M:16:1:28;9M0:32:1:26;9M2:16:106:28;9M4:16:1:28;9M6:32:79:28;9M8:32:51:28;9N:16:20:22;9O:8:1:36;9P:8:1:36;9Q:8:1:36;9R:8:1:36;9S:8:1:36;9S4:1:1:14;9T:8:1:36;9U:8:1:36;9U5:8:1:36;9V:16:60:28;9W:16:81:28;9X:8:1:36;9Y:4:51:9;9Z:4:46:9;A2:8:1:38;A3:32:20:32;A4:16:75:21;A5:16:1:22;A6:16:81:21;A7:16:66:21;A8:8:1:35;A9:16:20:21;AA:2:160:3;AB:2:143:3;AC:2:145:3;AC3:16:79:22;AC4:16:79:23;AD:2:137:3;AE:2:132:3;AF:2:124:3;AG:2:120:3;AH:2:75:3;AH8S:32:1:32;AI:2:133:3;AJ:2:111:3;AK:2:118:3;AP:16:40:21;AQ:16:1:21;AR:16:1:21;AS:16:1:21;AT:16:51:22;AU:16:1:22;AV:16:1:22;AW:16:1:22;AY:4:56:13;AZ:4:51:13;B0:16:20:24;B1:16:32:24;B2:16:1:24;B3:16:1:24;B4:16:46:24;B5:16:20:24;B6:16:1:24;B7:16:40:24;B8:16:1:24;B9:16:1:24;BA:16:118:24;BB:16:1:24;BC:16:1:24;BD:16:138:24;BE:16:1:24;BF:16:1:24;BG:16:145:24;BH:16:138:24;BI:16:130:24;BJ:16:1:24;BK:16:1:24;BL:16:1:24;BQ9:16:1:24;BR:16:1:24;BS:16:1:24;BS7:16:1:27;BT:16:1:24;BV:16:71:24;BV9:16:1:24;BY:16:105:24;BZ:16:1:24;C2:32:20:31;C3:1:56:14;C4:16:46:20;C5:8:40:35;C8:8:1:37;C9:24:1:24;CA:4:93:12;CB:4:95:12;CC:4:1:12;CD:4:63:12;CE:4:127:12;CE0:4:20:12;CE9:68:1:12;CF:2:1:5;CG:2:1:5;CH:2:1:5;CI:2:1:5;CJ:2:20:5;CK:2:32:5;CN:8:79:33;CN2:8:32:33;CP:4:32:10;CR8:48:1:22;CT:1:142:14;CT3:8:69:33;CU:1:73:14;CV:4:40:13;CW:4:56:13;CX:4:112:13;CY:2:1:5;CZ:2:1:5;D2:8:46:36;D3:8:1:36;D4:8:66:35;D5:8:1:35;D6:8:1:39;D7:16:1:25;D8:16:1:25;D9:16:32:25;DA:1:125:14;DB:1:125:14;DC:1:129:14;DD:1:121:14;DE:1:1:14;DF:1:166:14;DG:1:152:14;DH:1:136:14;DI:1:1:14;DJ:1:154:14;DK:1:176:14;DL:1:210:14;DM:1:156:14;DN:1:88:14;DO:1:158:14;DP:1:103:14;DQ:1:86:14;DR:1:117:14;DS:16:94:25;DT:16:1:25;DU:32:108:27;DV:32:87:27;DW:32:51:27;DX:32:91:27;DY:32:46:27;DZ:32:51:27;E2:16:99:26;E3:8:1:37;E4:16:1:20;E5:32:1:32;E6:32:20:32;E7:1:137:15;EA:1:193:14;EA6:1:102:14;EA8:8:127:33;EA9:8:56:33;EB:1:115:14;EC:1:117:14;ED:1:119:14;EE:1:96:14;EF:1:103:14;EG:1:69:14;EH:1:40:14;EI:1:139:14;EJ:1:1:14;EK:16:51:21;EL:8:20:35;EM:1:63:16;EN:1:20:16;EO:1:1:16;EP:16:20:21;EQ:16:1:21;ER:1:97:16;ES:1:137:15;ET:8:20:37;EU:1:110:16;EV:1:51:16;EW:1:120:16;EX:16:66:17;EY:16:60:17;EZ:16:1:17;F:1:204:14;FA:1:1:14;FB:1:1:14;FB8:8:1:39;FC:1:1:14;FD:1:1:14;FE:1:20:14;FF:8:32:35;FH:8:1:39;FI:1:1:14;FI8:16:1:26;FK:32:51:32;FL:1:1:14;FN:1:1:14;FN8:16:1:22;FO:32:32:32;FO0:32:1:32;FQ:1:1:14;FQ8:8:1:36;FR:8:40:39;FR/E:8:1:39;FR/G:8:1:39;FR/J:8:1:39;FR/T:8:1:39;FT:1:1:14;FT5W:8:1:39;FT5X:8:1:39;FT5Z:8:1:39;FU:1:1:14;FV:1:1:14;FW:32:40:32;FX:1:1:14;FY:4:32:9;FZ:1:1:14;G:1:197:14;GA:1:1:14;GB:1:1:14;GC:1:32:14;GD:1:46:14;GE:1:77:14;GF:1:20:14;GG:1:1:14;GH:1:20:14;GI:1:102:14;GJ:1:56:14;GK:1:1:14;GL:1:1:14;GM:1:138:14;GN:1:1:14;GO:1:1:14;GP:1:1:14;GQ:1:1:14;GR:1:20:14;GS:1:51:14;GT:1:32:14;GU:1:71:14;GV:1:1:14;GW:1:122:14;GX:1:86:14;GY:1:1:14;GZ:1:1:14;H2:16:20:20;H3:2:1:7;H4:32:20:28;H40:32:20:28;H5:8:1:38;H8:2:1:7;H9:2:20:7;HA:1:171:15;HB:1:170:14;HB0:1:71:14;HC:4:77:10;HC8:4:32:10;HD:4:20:10;HD8:4:40:10;HF:1:95:15;HF0:4:32:13;HG:1:128:15;HJ:4:71:9;HK:4:108:9;HK0:4:1:9;HL:16:113:25;HM:16:1:25;HN:16:1:21;HO:2:1:7;HP:2:79:7;HS:16:108:26;HV:1:20:15;HW:1:1:14;HX:1:1:14;HY:1:1:14;HZ:16:81:21;I:1:216:15;I1:1:98:15;I5:8:79:37;IM0:1:1:15;IS0:1:107:15;J2:8:1:37;J5:8:1:35;JA:16:184:25;JB:16:1:25;JC:16:1:25;JD:16:1:25;JD1:48:32:27;JE:16:145:25;JF:16:139:25;JG:16:133:25;JH:16:165:25;JI:16:126:25;JJ:16:136:25;JK:16:137:25;JL:16:122:25;JM:16:122:25;JN:16:110:25;JO:16:111:25;JP:16:105:25;JQ:16:110:25;JR:16:150:25;JR6:16:84:25;JS:16:107:25;JT:16:60:23;JU:16:20:23;JV:16:1:23;JW:1:40:40;JX:1:1:40;JY:16:20:20;JZ:32:1:28;JZ0:32:1:28;K:2:255:3;KC4:64:115:12;KH0:32:20:27;KH1:32:1:31;KH2:32:46:27;KH3:32:1:31;KH4:32:1:31;KH5:32:1:31;KH5K:32:1:31;KH6:32:99:31;KH7:32:63:31;KH7K:32:1:31;KH8:32:1:32;KH8S:32:1:32;KH9:32:1:31;KP1:2:1:8;KR6:16:46:25;KR8:16:46:25;L2:4:20:13;L3:4:32:13;L4:4:1:13;L5:4:1:13;L6:4:1:13;L7:4:51:13;L8:4:1:13;L9:4:1:13;LA:1:139:14;LB:1:109:14;LC:1:105:14;LD:1:1:14;LE:1:1:14;LF:1:1:14;LG:1:20:14;LH:1:1:14;LI:1:1:14;LJ:1:1:14;LK:1:1:14;LL:1:1:14;LM:1:1:14;LN:1:75:14;LO:4:32:13;LP:4:40:13;LQ:4:56:13;LR:4:32:13;LS:4:51:13;LT:4:88:13;LU:4:146:13;LV:4:63:13;LW:4:94:13;LX:1:95:14;LY:1:144:15;LZ:1:165:20;M:1:185:14;M2:1:73:14;M4:1:69:14;MA:1:1:14;MB:1:1:14;MD:1:51:14;ME:1:63:14;MF:1:1:14;MG:1:1:14;MH:1:1:14;MI:1:100:14;MK:1:1:14;ML:1:1:14;MM:1:122:14;MN:1:1:14;MO:1:1:14;MP:1:20:14;MQ:1:1:14;MR:1:1:14;MS:1:20:14;MT:1:1:14;MU:1:46:14;MV:1:1:14;MX:1:71:14;MY:1:1:14;MZ:1:1:14;N:2:232:3;NH8S:32:1:32;NP1:2:1:8;OA:4:77:10;OB:4:1:10;OC:4:1:10;OD:16:51:20;OE:1:159:15;OF:1:1:15;OG:1:112:15;OH:1:166:15;OH0:1:73:15;OH0M:1:20:15;OI:1:40:15;OJ0:1:20:15;OK:1:183:15;OL:1:120:15;OM:1:158:15;ON:1:173:14;OO:1:71:14;OP:1:84:14;OQ:1:71:14;OR:1:100:14;OS:1:63:14;OT:1:105:14;OY:1:51:14;OZ:1:141:14;P2:32:1:28;P3:16:71:20;P4:4:73:9;P5:16:1:25;P6:16:1:25;P7:16:1:25;P8:16:1:25;P9:16:1:25;PA:1:174:14;PB:1:86:14;PC:1:110:14;PD:1:154:14;PE:1:134:14;PF:1:77:14;PG:1:87:14;PH:1:83:14;PI:1:114:14;PJ2:4:60:8;PJ4:4:71:9;PJ5:2:32:8;PJ6:2:32:8;PJ7:4:46:8;PJ8:2:1:8;PJ9:4:1:9;PK:32:1:28;PK1:32:1:28;PK2:32:1:28;PK3:32:1:28;PK4:32:1:28;PK5:32:1:28;PK6:32:1:28;PL:32:1:28;PM:32:1:28;PN:32:1:28;PO:32:1:28;PP:4:137:11;PP0F:4:1:11;PP0S:4:1:11;PP0T:4:1:11;PQ:4:60:11;PR:4:105:11;PS:4:91:11;PT:4:122:11;PU:4:155:11;PV:4:91:11;PW:4:90:11;PX:4:88:11;PY:4:181:11;PZ:4:51:9;R1FJ:1:1:40;R1MV:1:1:16;RA:17:161:16;RB:17:1:16;RC:17:123:16;RD:17:114:16;RE:17:1:16;RF:17:40:16;RG:17:92:16;RH:17:1:16;RI:17:1:16;RJ:17:69:16;RK:17:131:16;RL:17:107:16;RM:17:112:16;RM1V:1:1:16;RN:17:129:16;RO:17:91:16;RP:17:1:16;RQ:17:79:16;RR:17:1:16;RS:17:1:16;RT:17:119:16;RU:17:129:16;RV:17:119:16;RW:17:136:16;RX:17:114:16;RY:17:101:16;RZ:17:122:16;S0:8:32:33;S2:16:51:22;S3:16:1:22;S4:8:1:38;S5:1:167:15;S6:16:1:28;S7:8:32:39;S8:8:1:38;S9:8:1:36;SA:1:99:15;SB:1:63:15;SC:1:51:15;SD:1:75:15;SE:1:99:15;SF:1:69:15;SG:1:79:15;SH:1:20:15;SI:1:51:15;SJ:1:56:15;SK:1:92:15;SL:1:1:15;SM:1:146:15;SN:1:136:15;SO:1:113:15;SP:1:191:15;SQ:1:162:15;SR:1:1:15;SSA:8:1:34;SSB:8:1:34;SSC:8:1:34;SSD:8:1:34;SSE:8:1:34;SSF:8:1:34;SSG:8:1:34;SSH:8:1:34;SSI:8:1:34;SSJ:8:1:34;SSK:8:1:34;SSL:8:1:34;SSM:8:1:34;SSN:8:1:34;SSO:8:1:34;SSP:8:1:34;SSQ:8:1:34;SSR:8:1:34;SSS:8:1:34;SST:8:1:34;SSU:8:1:34;SSV:8:1:34;SSW:8:1:34;SSX:8:1:34;SSY:8:1:34;SSZ:8:1:34;ST:8:1:34;ST0:8:1:34;SU:8:40:34;SV:1:152:20;SV/A:1:1:20;SV5:1:69:20;SV9:1:81:20;SW:1:20:20;SX:1:81:20;SY:1:66:20;SZ:1:69:20;T2:32:1:31;T30:32:20:31;T31:32:1:31;T32:32:20:31;T33:32:1:31;T5:8:1:37;T7:1:56:15;T8:32:51:27;T9:1:1:15;TA:17:136:20;TB:17:20:20;TC:17:83:20;TF:1:86:40;TH:1:1:14;TJ:8:1:36;TK:1:73:15;TL:8:20:36;TM:1:137:14;TN:8:1:36;TO:1:83:14;TP:1:20:14;TQ:1:1:14;TR:8:20:36;TT:8:20:36;TU:8:1:35;TV:1:1:14;TW:1:1:14;TX:32:1:30;TY:8:32:35;TZ:8:20:35;UA2:1:56:15;UJ:16:1:17;UK:16:60:17;UL:16:1:17;UM:16:1:17;UN:16:116:17;UN1:1:20:16;UO:16:20:17;UP:16:66:17;UQ:16:1:17;UR:1:137:16;US:1:117:16;UT:1:139:16;UU:1:1:16;UV:1:46:16;UW:1:100:16;UX:1:96:16;UY:1:91:16;UZ:1:81:16;V5:8:63:38;V6:32:32:27;V7:32:32:31;V8:32:51:28;V9:8:1:38;VA:2:167:5;VB:2:32:5;VC:2:81:5;VD:2:1:5;VE:2:193:5;VF:2:20:5;VG:2:1:5;VK:32:156:29;VK0:40:1:30;VK9:32:32:28;VK9C:32:20:29;VK9L:32:1:30;VK9M:32:1:30;VK9N:32:1:32;VK9W:32:1:30;VK9X:32:1:29;VO:2:100:5;VP:1:91:14;VP6:32:20:32;VP8:4:46:13;VQ:1:32:14;VQ1:8:1:37;VQ6:8:1:37;VQ9:8:1:39;VR:16:87:24;VS:1:1:14;VS2:48:1:28;VS4:32:1:28;VS9A:16:1:21;VS9H:16:1:21;VS9K:16:1:21;VS9P:16:1:21;VS9S:16:1:21;VT:16:1:22;VU:16:124:22;VV:16:1:22;VW:16:1:22;VX:2:20:5;VY:2:100:5;W:2:243:3;WH8S:32:1:32;WP1:2:1:8;XA:2:1:6;XB:2:1:6;XC:2:1:6;XD:2:1:6;XE:2:124:6;XF:2:20:6;XG:2:1:6;XH:2:1:6;XI:2:1:6;XJ:2:1:5;XK:2:1:5;XL:2:40:5;XM:2:1:5;XN:2:1:5;XO:2:20:5;XQ:4:77:12;XR:4:56:12;XS:16:1:24;XT:8:1:35;XU:16:32:26;XV:16:1:26;XV9:32:63:26;XW:16:32:26;XX9:16:32:24;XY:16:1:26;XZ:16:1:26;Y2:1:1:14;Y3:1:1:14;Y4:1:1:14;Y5:1:1:14;Y6:1:1:14;Y7:1:1:14;Y8:1:1:14;Y9:1:1:14;YA:16:1:21;YB:32:170:28;YC:32:172:28;YD:32:162:28;YE:32:118:28;YF:32:134:28;YG:32:138:28;YH:32:1:28;YI:16:20:21;YJ:32:32:32;YK:16:1:20;YL:1:129:15;YM:16:79:20;YO:1:168:20;YP:1:79:20;YQ:1:63:20;YR:1:88:20;YT:1:143:15;YU:1:148:15;YV:4:96:9;YW:4:32:9;YX:4:1:9;YY:4:63:9;YZ:1:1:15;Z2:8:1:38;Z3:1:105:15;Z6:1:69:15;Z8:8:1:34;ZA:1:63:15;ZB:1:20:14;ZB2:1:40:14;ZC4:16:32:20;ZC5:32:1:28;ZC6:16:1:20;ZD:1:1:14;ZD4:8:1:35;ZD7:8:51:36;ZD8:8:1:36;ZD9:8:20:38;ZE:1:1:14;ZG:1:1:14;ZH:1:1:14;ZI:1:1:14;ZJ:1:1:14;ZK:32:1:32;ZK1:32:1:32;ZK2:32:1:32;ZK3:32:1:31;ZL:32:120:32;ZL7:32:32:32;ZL8:32:1:32;ZL9:32:1:32;ZM:32:56:32;ZN:1:1:14;ZO:1:1:14;ZP:4:87:11;ZQ:1:1:14;ZR:8:32:38;ZS:8:102:38;ZS0:8:1:38;ZS8:8:1:38;ZS9:8:20:38;ZT:8:1:38;ZU:8:1:38;ZV:4:90:11;ZW:4:86:11;ZX:4:66:11;ZY:4:87:11;ZZ:4:91:11"

    val prefixes: List<Entry> by lazy {
        ENCODED.split(';').map {
            val parts = it.split(':')
            Entry(parts[0], parts[1].toInt(), parts[2].toInt(), parts[3].toInt())
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
    fun randomCallsign(lengthOpt: Int, regionOpt: Int, commonOnly: Boolean): String =
        randomCallInfo(lengthOpt, regionOpt, commonOnly).call

    /** Like [randomCallsign], plus continent and CQ zone of the chosen prefix (QSO Bot). */
    fun randomCallInfo(lengthOpt: Int, regionOpt: Int, commonOnly: Boolean): CallInfo {
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
        val chosen = weightedPick(matching)
            ?: return CallInfo(randomFallbackCall(), CONT_ALL, 0)

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
        return CallInfo(sb.toString(), chosen.continent, chosen.cqZone)
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
    private fun randomVkZl(): CallInfo {
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
        return CallInfo(sb.toString(), CONT_OC, if (isVK) 29 else 32)
    }
}
