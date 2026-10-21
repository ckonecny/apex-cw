import os,sys
from PIL import Image
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','img')
M=os.path.dirname(os.path.abspath(__file__))
names={  # captured name -> manual name
 'home':'home','freemodes':'freemodes','games':'games','res_hub':'res_hub','links':'links','chart':'chart',
 'achievements':'achievements','achievements_settings':'achievements_settings','settings1':'settings1','settings2':'settings2',
 'hear_start':'hear_start','hear_stats':'hear_stats','hear_progress':'hear_progress','hear_progress_b':'hear_progress2',
 'hear_char_detail':'hear_char_detail','hear_trends':'hear_trends',
 'understand':'understand','headcopy_setup':'headcopy_setup','qgroups_setup':'qgroups_setup','miniqso_setup':'miniqso_setup','exam_setup':'exam_setup','hear_sheet_0':'hear_sheet1','hear_sheet_1':'hear_sheet2','hear_sheet_3':'hear_sheet4','echo_sheet_2':'echo_sheet',
 'keyer':'keyer','keyer_sheet':'keyer_sheet','decoder':'decoder','decoder_sheet':'decoder_sheet','wifi':'wifi','adv_select':'adv_select','inv_lobby':'inv_lobby','morsel_lobby':'morsel_lobby','mc_lobby':'mc_lobby','tb_lobby':'tb_lobby','pu_lobby':'pu_lobby','rc_lobby':'rc_lobby',
 'echo_answer':'echo_answer','echo_result':'echo_result','echo_result2':'echo_result2',
 'hear_sending':'hear_sending','hear_mark':'hear_mark','hear_revealed':'hear_revealed','hear_result':'hear_result','hear_weak':'hear_weak','hear_type':'hear_type','hear_type_retry':'hear_type_retry','hear_type_learn':'hear_type_learn','hear_type_sent':'hear_type_sent',
 'headcopy_listen':'headcopy_listen','headcopy_question':'headcopy_question','headcopy_result':'headcopy_result','qgroups_question':'qgroups_question','qgroups_result':'qgroups_result','qgroups_cheat':'qgroups_cheat','miniqso_listen':'miniqso_listen','miniqso_question':'miniqso_question','miniqso_result':'miniqso_result',
 'char_sheet':'char_sheet','inv_game':'inv_game',
 'own_library':'own_library','own_player':'own_player','own_sheet':'own_sheet','qso':'qso','qso_sheet':'qso_sheet',
 'adv_game':'adv_game','adv_help':'adv_help','adv_map':'adv_map','adv_map_warn':'adv_map_warn','adv_map_whole':'adv_map_whole','adv_saves':'adv_saves','adv_settings':'adv_settings','adv_settings2':'adv_settings2',
 'tree_letters':'tree_letters','tree_deep':'tree_deep','tree_letters_land':'tree_letters_land','tree_deep_land':'tree_deep_land',
 'char_practice':'char_practice',
 'echo_start':'echo_start','echo_stats':'echo_stats','echo_progress':'echo_progress','echo_char_detail':'echo_char_detail','echo_trends':'echo_trends'}
only=set(sys.argv[1:])
for lang in('de','en'):
    for src,dst in names.items():
        if only and dst not in only: continue
        p=f'{M}/out/{lang}/{src}.png'
        if not os.path.exists(p): print('missing',lang,src); continue
        Image.open(p).convert('RGB').quantize(128,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).save(f'{R}/{lang}/{dst}.png',optimize=True)
print('installed')
