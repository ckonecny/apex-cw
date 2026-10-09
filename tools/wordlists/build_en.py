import re,sys
names={l.strip().lower() for l in open('/usr/share/dict/propernames')}
web2=set(); caps=set()
for l in open('/usr/share/dict/web2',encoding='latin-1'):
    w=l.strip()
    if w[:1].isupper(): caps.add(w.lower())
    else: web2.add(w)
# only-capitalised in web2 => proper noun
propers=caps-web2
slang=set("""yeah   ok hey   gonna wanna gotta gimme lemme dunno ain nah yep yup nope huh uh um hmm hm oh ah aah ooh whoa wow ha haha hah heh eh ugh mm mmm shh sh psst ya yo oops ow ooo oo hmmm uhh umm ahh ohh aw aww  mr mrs ms dr jr sr  mum mommy daddy mama papa       
fuck fucking fucked fucker shit shitty bullshit damn damned goddamn goddamnit hell bitch bitches bastard ass asshole dick cock pussy whore slut sex sexy sexual rape raped rapist nigger nigga fag faggot gay penis cum cunt crap piss pissed drunk dope porn naked nude tits boobs    killer murder murdered      suicide      
jesus christ  """.split())
keepw=set(['the', 'no', 'will', 'think', 'those', 'guy', 'old', 'trying', 'real', 'part', 'case', 'women', 'anymore', 'paid', 'space', 'box', 'list', 'major', 'proud', 'rich', 'became', 'price', 'earlier', 'held', 'dropped', 'began', 'planned', 'committed', 'page', 'spy', 'shadow', 'leads', 'internet', 'plastic', 'online', 'hunter', 'mark', 'bill', 'art', 'ray', 'grant', 'drew', 'rob', 'grace', 'pilot', 'judge', 'king', 'hang', 'win', 'feet', 'gentlemen', 'anytime', 'meantime', 'kidnapped', 'robbed', 'boxes', 'goodnight', 'girlfriend', 'boyfriend', 'sergeant'])
CRIME=re.compile(r'\b(?:crim|thie[fv]|steal|stole|stolen|rob(?:s|bed|bing|ber)|burglar|theft|fraud|forg(?:e|ed|ery)\b|smuggl|launder|bribe|corrupt|illegal|illicit|unlawful|felon|convict|guilty|innocent|sentenc|trial|court|judge|jury|attorney|lawyer|prosecut|defendant|witness|testif|evidence|suspect|detective|investigat|inspector|sheriff|warrant|custody|bail\b|inmate|cell\b|cells\b|gangster|mob\b|thug|dealer|dealing|cartel|trafficking|spy|spies|conspir|betray|traitor|blackmail|extort|ransom|hijack|fugitive|escape|escaped|cheat|scam|lie[sd]?\b|liar|lying|swindl|con\b|cons\b|undercover|alibi|confess|punish|revenge|sin\b|sins\b|evil|drug|dope|weed|pot\b|coke|cocaine|heroin|cannabis|marijuana|opium|meth\b|pills?\b|overdose|addict|junkie|booze|vodka|whisk|beer|wine|liquor|alcohol|drunk|sober|smok|cigar|tobacco|nicotine|medication|prescription|narcotic|inject|needle|syringe|gambl|casino|poker|bet\b|bets\b|betting|lottery|bar\b|bars\b|pub\b|brew|champagne|cocktail|martini|rum\b|gin\b|poison|bug\b|bugs\b)')
VIOL=re.compile(r'kill|murder|blood|bleed|\bguns?\b|gunm|gunshot|gunfire|shoot|\bshots?\b|bomb|weapon|knife|knives|sword|stab|\bwars?\b|warrior|warfare|attack|fight|fought|punch|\bkick|wound|death|\bdead|\bdie[sd]?\b|dying|deadly|lethal|corpse|\bvictim|tortur|assault|bullet|rifle|pistol|grenade|explo[ds]|army|armed|troops?\b|soldier|military|enemy|enemies|battle|revenge|threat|violen|brutal|slaughter|massacre|execut|hang(?:ed|ing)?\b|choke|strangle|beat(?:en|ing|s)\b|\bbeat\b|hurt|harm|destroy|crush|slap|smash|rage|angry|anger|hate|hated|hates|hating|devil|demon|hell\b|cruel|evil|gang\b|gangs|mafia|riot|rebel|hostage|kidnap|robber|robbery|crime|criminal|prison|jail|arrest|police|cops?\b|cancer|disease|virus|poison|toxic|nuclear|terror|suffer|scream|panic|danger|bury|buried|grave|funeral|coffin|ghost|haunt|skull|bones?\b|bat\b|ammo|trigger|hunt|trap(?:ped)?\b|vampire|monster|beast|witch|curse|nightmare|disaster|crash|ruin|damage|wreck|burn|fire[sd]?\b|firing|slave|drug|alcohol|liquor|drunk|gambl')
BRIT=re.compile(r'colour|favour|honour|neighbour|behaviour|humour|labour|rumour|harbour|flavour|savour|armour|odour|vapour|centre|theatre|metre|litre|fibre|realis|recognis|organis|apologis|criticis|emphasis(?:e|ed|es|ing)\b|analys(?:e|ed|es|ing)\b|defence|offence|licence|cheque|travell|tyre|programme|judgement|ageing|jewellery|aluminium|storey|kerb|pyjama|plough|sceptic|cosy|whilst|\bgrey|\bmum\b|\bmummy\b|\bmums\b|\bmum[s]?\b|lorry|petrol|holidays?\b(?!x)|\bflat\b|\bbloke|\bbrilliant|\bcolou?r|labell|modell|cancell|signall|fuelled|counsell|marvell|centimetre|catalogue|dialogue|grey|mould|sulph|\btoward[s]\b')
rows=[]
for l in open('fw/en_50k.txt'):
    w,c=l.split(); c=int(c)
    if not re.fullmatch(r'[a-z]{2,10}',w): continue
    if w in set('coward conflict drown radiation bodies breasts whimpering muffled roaring honking chanting shouts kang khan yang chan harper benny holmes riley nelson quinn mel han dont yen sire warrant ward shouts yells yelling giggles coughs sighing chirping rumbling whistling'.split()): continue
    if CRIME.search(w): continue
    if VIOL.search(w) or BRIT.search(w): continue
    if w in {'chuckling', 'freaking', 'growling', 'sec', 'fat', 'screw', 'victims', 'horny', 'gasping', 'barking', 'cigarette', 'sync', 'nazi', 'terrorist', 'exhales', 'miller', 'alcohol', 'murders', 'maya', 'suck', 'liquor', 'morons', 'corpse', 'losers', 'whores', 'joey', 'slave', 'kissing', 'coke', 'murderers', 'sobbing', 'pickin', 'drug', 'thy', 'rita', 'somethin', 'panting', 'pee', 'los', 'stupid', 'sin', 'kissed', 'bum', 'sucker', 'ugly', 'goin', 'cos', 'virgin', 'slaves', 'buzzing', 'nothin', 'sucked', 'wailing', 'gambling', 'comin', 'monsieur', 'chattering', 'suicide', 'cigarettes', 'blah', 'dumb', 'cooper', 'weed', 'butt', 'whirring', 'jerk', 'sammy', 'idiot', 'moron', 'nazis', 'subtitles', 'butts', 'homicide', 'jenny', 'drugs', 'lily', 'coughing', 'germans', 'kiss', 'torture', 'woo', 'scoffs', 'bastards', 'thou', 'assault', 'san', 'screwed', 'screeching', 'hitler', 'loser', 'shut', 'heck', 'madame', 'nude', 'sucks', 'ouch', 'moaning', 'russians', 'smith', 'freak', 'hong', 'kissin', 'cigar', 'ass', 'stub', 'rapist', 'lucy', 'parker', 'crap', 'naked', 'gosh', 'lookin', 'thee', 'angeles', 'groaning', 'idiots', 'thine', 'freaked', 'gee', 'murderer', 'fatty'} or w in slang or w in {'didn','doesn','isn','wasn','haven','couldn','wouldn','aren','shouldn','hasn','hadn','weren','mustn','needn','em'}: continue
    if w in names or w in propers:
        if w not in keepw: continue
    if len(w)==2 and w not in set("am an as at be by do go he if in is it me my no of oh on or so to up us we".split()): continue
    # drop word unless real dictionary word or plausible inflection
    base=[w]+[w[:-len(s)]+r for s,r in (('s',''),('es',''),('ies','y'),('ed',''),('d',''),('ing',''),('er',''),('ly',''),('est',''),('ied','y'),('n',''))  if w.endswith(s)]
    base+= [w[:-3] for _ in [0] if w.endswith('ing')]
    base+= [w[:-3]+'e' for _ in [0] if w.endswith('ing')]
    base+= [w[:-2]+'e' for _ in [0] if w.endswith('ed')]
    if len(w)>=3 and w[-1]==w[-2]: pass
    if w.endswith(('ing','ed')) and len(w)>5: base.append(w[:-3] if w.endswith('ing') else w[:-2])
    if w.endswith(('ing','ed')) and len(w)>5 and w[-4]==w[-5]: base.append(w[:-4] if w.endswith('ing') else w[:-3])
    if w not in keepw and not any(b in web2 for b in base): continue
    rows.append((w,c))
N=int(sys.argv[1]) if len(sys.argv)>1 else 4000
rows=rows[:N]
open('words_candidate.txt','w').write(''.join(f'{w} {c}\n' for w,c in rows))
print(len(rows), rows[-1])
