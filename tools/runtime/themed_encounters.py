"""Theme-bound silhouettes and encounter roles, shared by authoring and art prompts."""
from environment_themes import THEMES

# Each row owns twelve silhouettes, rather than painting the same creature twelve colours.
FAMILIES = [
    ("灯市", "灯耳鼠/灯笼耳朵的小鼠;烛尾雀/火芯尾巴的折纸雀;招幌狐/背着店幌的窄狐;伞棚蟹/撑着红棚的宽蟹;提灯童/提着六角灯的瘦纸童;绸帽獾/戴卷绸帽的胖獾;糖灯蛙/透明蜜灯肚子的矮蛙;铺门守/木店门组成的高护卫;灯串蛇/多节圆灯拼成的长蛇;纸鼓蜂/鼓形肚子的微型蜂;灯绳蛛/八条灯绳腿的蜘蛛;烛车犀/轮式烛台组成的重犀",
     "百灯铺主/灯笼摊车合成的巨型四脚店主;绸棚夜巡/带巨大棚翼和灯绳的高夜巡;蜜火灯母/蜜蜡灯腹和八条纸绸臂的圆灯母"),
    ("河埠", "舟壳鼠/小木船壳上的绳尾鼠;苇尾雀/芦苇尾的蓝纸雀;桨爪狐/双桨爪的窄水狐;泊舟蟹/宽木船身与桨腿的蟹;缆绳童/蓝蓑衣和绳腿的船童;浮桶獾/木浮桶身子的胖獾;渔篓蛙/竹渔篓肚的水蛙;渡牌守/船舷木牌组成的长护卫;缆结蛇/蓝色系泊绳和浮球组成的蛇;纸帆蜂/小纸帆双翼的舟蜂;绳锚蛛/锚脚绳腹的宽水蛛;沉舟犀/沉船船首组成的重水犀",
     "潮桨舟王/巨大蓝色船首与双木桨臂的舟王;缆渊织母/系泊绳和浮桥组成的八臂织母;纸帆吞浪/巨型折帆海兽与蓝色浪尾"),
    ("钱库", "钱耳鼠/方孔铜钱耳的小鼠;金签雀/金箔尾的小雀;金链狐/三条金币链尾的窄狐;铸盘蟹/圆铸币盘组成的宽蟹;秤盘童/持金币秤盘的小童;钱袋獾/两只黄铜大钱袋构成的胖獾;金瓮蛙/黄金钱瓮组成的矮蛙;库门守/厚圆铜库门组成的高护卫;钱串蛇/层层方孔铜钱连接的长蛇;金翅蜂/薄金箔翅膀的微蜂;算盘蛛/黄铜算盘腹和珠脚蜘蛛;金库犀/带巨大方孔币头的重金库犀",
     "铸钱巨匠/双臂铸币压力锤与圆钱甲的大匠;金瓮聚财/巨大金瓮肚和垂落铜钱链的兽;千珠算首/宽黄铜算盘与许多珠臂组成的判首"),
    ("苔庭", "苔耳鼠/圆蕨叶耳的小绿鼠;花芯雀/白花冠和叶尾雀;根尾狐/细根长尾与绿苔背的狐;蕨壳蟹/圆蕨叶壳的宽蟹;花芽童/花芽头和嫩根腿的小童;根窝獾/圆苔窝身体的胖獾;苔泉蛙/小石泉背上的绿蛙;树篱守/活树篱组成的高守卫;藤结蛇/嫩藤缠白花的长蛇;花粉蜂/花粉袋腹的小蜂;根须蛛/八条细树根腿的花蛛;根庭犀/巨根木甲与苔角重犀",
     "蕨冠庭主/巨蕨冠和弯曲根臂的花庭长老;根巢伏兽/巨大苔根窝壳的伏兽;春灯花母/白花灯冠与多条嫩绿藤臂的花母"),
    ("书院", "卷耳鼠/卷轴耳和墨尾小鼠;墨冠雀/蓝墨冠的纸雀;书页狐/多层卷页尾的窄狐;砚台蟹/方蓝砚台身体的宽蟹;笔筒童/长笔筒帽和卷轴衣的小童;书匣獾/双层蓝书匣身体的胖獾;墨瓮蛙/墨瓮腹和灰蓝纸肢的蛙;书架守/高蓝木书架甲的长护卫;长卷蛇/被墨痕缠住的长卷纸蛇;签页蜂/蓝书签翼的小蜂;笔杆蛛/八支竹笔腿的砚蛛;书车犀/巨型书柜和粗笔角的重犀",
     "卷海院长/巨型蓝纸卷袍与墨笔杖的院长;砚渊玄兽/巨大黑蓝砚台甲壳与墨鳞的兽;千笔墨师/多支长笔臂与白纸卷冠的墨师"),
    ("戏楼", "绸耳鼠/玫红绸耳的小鼠;羽冠雀/紫戏羽冠的小雀;幕尾狐/三条梅紫帘尾的狐;戏台蟹/小紫木戏台和幕帘壳的蟹;戏偶童/窄玫紫戏偶与木操杆;绸卷獾/大卷紫绸胖肚子的獾;面谱蛙/戏面谱背壳的矮蛙;景屏守/高玫紫折景屏护卫;绸缎蛇/长紫绸与竹扇骨组成的蛇;羽扇蜂/紫羽扇翼的小蜂;牵线蛛/幕布腹与戏偶杆脚蜘蛛;戏车犀/宽大舞台推车和面谱头的重犀",
     "紫幕班主/巨大玫紫舞台帐篷甲与操偶臂的班主;绸海戏后/多层梅紫绸裙和扇骨爪的戏后;千面傀王/高紫折景架中数层戏面与木杆手"),
    ("烛堂", "蜡耳鼠/融蜡圆耳的小骨鼠;烛芯雀/奶白羽翼和短烛芯雀;白蜡狐/细长流蜡尾的狐;蜡台蟹/圆白烛台甲壳的宽蟹;烛骨童/长奶白骨蜡腿的烛童;融蜡獾/大融蜡滴肚子的胖獾;白瓮蛙/白蜡瓮肚的蛙;蜡柱守/高融蜡柱甲与双烛臂;烛节蛇/串联白蜡烛节的长蛇;蜡羽蜂/半透明蜡羽翼的小蜂;烛骨蛛/细蜡骨八腿的蜘蛛;蜡座犀/宽象牙烛座甲与白骨角犀",
     "融蜡圣母/巨大奶白流蜡裙与细骨烛冠;烛骨龟王/巨烛台龟甲与蜡骨爪的王;白焰钟使/巨大白蜡钟腹和双骨蜡铃臂"),
    ("雷门", "雷耳鼠/紫色雷纹鼓耳的小鼠;电羽雀/锯齿蓝电羽的小雀;紫雷狐/三条分叉电纹尾的狐;雷鼓蟹/紫鼓身与铜电杆腿的宽蟹;电纹童/蓝紫纸甲和闪电帽小童;风鼓獾/圆紫鼓腹的胖獾;雷瓮蛙/紫雷瓮腹的山蛙;雷石守/高紫岩甲与蓝电纹护卫;电索蛇/蓝电索与紫岩节组成的蛇;电翼蜂/锯齿闪电翼的小蜂;雷丝蛛/蓝雷网腹与细紫杆脚蛛;紫岩犀/重紫山岩甲和电角巨犀",
     "紫霆鼓尊/巨型紫鼓与双电杆臂的雷尊;裂岳雷兽/巨大紫岩甲和分叉蓝雷角的兽;风雷门将/高山门形肩甲与蓝电双盾门将"),
    ("灰窑", "炉耳鼠/小炉口耳和焦木尾鼠;灰翅雀/灰烬羽翼和火炭腹雀;炉尾狐/三条煤炭管尾的狐;陶窑蟹/圆黑陶窑身的宽蟹;烟囱童/瘦烟囱帽和焦纸衣童;炭袋獾/煤袋肚子的胖獾;铜炉蛙/小铜炉腹的蛙;窑砖守/高焦砖甲与双炉锤臂;烟管蛇/长焦炉管组成的蛇;煤芯蜂/火芯和灰翼小蜂;铁钳蛛/八条铁钳脚和陶腹蜘蛛;窑车犀/宽窑车身与陶烟囱角的犀",
     "铜炉窑主/巨大陶炉腹和双铁钳臂的窑主;炭山伏魈/重焦黑陶甲与铜色炉口胸的猿兽;烟塔铸母/高黑烟囱冠和多条铜炉臂的匠母"),
    ("莲阁", "莲耳鼠/白莲瓣耳和玉尾鼠;莲芯雀/玉青莲籽肚和白羽雀;玉瓣狐/三条玉色莲瓣尾狐;莲座蟹/宽玉莲座甲的蟹;花灯童/白莲灯帽和薄荷纸衣童;莲籽獾/圆大玉莲蓬肚的胖獾;玉瓮蛙/小玉水瓮身的蛙;莲栏守/高玉栏甲和曲桥臂守卫;莲节蛇/串联薄荷莲节的蛇;花灯蜂/白花灯翼的玉蜂;荷须蛛/细荷梗八腿和玉叶腹蛛;水阁犀/宽玉亭甲和白莲角重犀",
     "玉莲阁主/巨大白莲冠与玉青亭座的阁主;莲池镇龟/大玉莲蓬龟甲和水纹爪;水镜莲母/白玉莲裙与多条莲梗臂的水母"),
    ("白桥", "绫耳鼠/白绫耳的小银鼠;霜羽雀/冰蓝羽翼和白绫尾雀;银绫狐/长银白绫尾狐;白桥蟹/小白石桥身与银绫爪蟹;绫帽童/长白绫帽和蓝纸骨童;霜绸獾/圆银白绸腹獾;银瓮蛙/白石瓮肚冰蛙;霜碑守/高浅蓝石碑甲护卫;白绫蛇/银白绫卷组成的蛇;冰帆蜂/小冰蓝纸帆翼蜂;银丝蛛/银白绫丝八腿蛛;霜桥犀/宽银白石桥甲和冰角犀",
     "霜绫桥后/巨大银白长绫冠与浅蓝桥裙的桥后;白桥镇兽/白石桥体和两只巨大银绫爪的兽;冷月绫使/高蓝白月环架与四条白绫臂"),
    ("钟楼", "钟耳鼠/小金铜钟耳的木鼠;铃羽雀/黄铜铃羽的小雀;摆钟狐/长木摆锤尾狐;齿轮蟹/大铜齿轮身的蟹;木锤童/细木锤帽和黄纸衣童;钟腹獾/大圆黄铜钟腹獾;黄钟蛙/小铜钟瓮身的蛙;楼梁守/高赭木楼梁与巨钟盾守卫;齿节蛇/一串黄铜齿轮组成的蛇;铃翅蜂/两片细铜钟翼蜂;摆针蛛/钟面腹和木摆针八腿蛛;楼钟犀/宽赭木楼台甲和粗钟锤角犀",
     "千钟楼主/巨大金铜钟冠与赭木重锤双臂;齿海钟兽/大铜齿轮壳和摆锤爪的兽;悬重木王/高赭木配重架与巨大黄钟腹的王"),
    ("竹林", "竹耳鼠/细竹叶耳的小绿鼠;叶羽雀/竹叶羽翼的小雀;竹根狐/三条细竹根尾狐;竹篱蟹/宽竹编壳的蟹;笋帽童/竹笋头和竹节腿童;竹篮獾/圆胖竹篮肚獾;竹筒蛙/空竹筒腹蛙;竹杆守/高竹节甲和双竹刃守卫;竹节蛇/长青竹节组成的蛇;竹叶蜂/薄竹叶翼的小蜂;竹丝蛛/编竹网腹和细竹杆脚蛛;竹根犀/重竹根甲和粗竹笋角犀",
     "竹冠林主/巨大竹叶冠和弯曲竹根臂的林主;竹巢伏虎/宽竹编甲与短竹刃爪的伏虎;契藤竹母/高竹栅架和多条青竹丝臂的竹母"),
    ("镜廊", "镜耳鼠/碎青镜耳小鼠;镜羽雀/窄冰青镜翼雀;镜尾狐/三条棱镜尾的狐;晶镜蟹/宽黑蓝镜甲蟹;棱面童/折冰青镜面头的细童;镜匣獾/方镜匣胖肚獾;镜瓮蛙/光滑蓝黑镜瓮身蛙;棱镜守/高三角镜甲护卫;镜鳞蛇/碎冰镜鳞组成的蛇;冰镜蜂/细冰青菱镜翼蜂;裂镜蛛/镜盘腹和碎镜八腿蛛;镜楼犀/宽黑蓝镜台甲和晶棱角犀",
     "镜海廊主/巨大黑蓝镜环与对称冰青镜盾;碎月镜兽/巨碎镜甲和月牙冰镜爪的兽;双面镜后/高棱镜冠和六条冰青镜刃臂的后"),
    ("石牢", "晶耳鼠/小紫晶耳黑鼠;封羽雀/紫封纸羽的小雀;链尾狐/细紫链长尾狐;封石蟹/宽紫封石甲的蟹;牢签童/方紫签帽和黑纸衣童;链匣獾/厚紫链匣胖肚獾;紫瓮蛙/紫封印瓮身的蛙;封门守/高紫牢门甲和封契双盾;紫节蛇/串联紫封石节的蛇;封纸蜂/紫几何符翼小蜂;链网蛛/紫链网腹和黑链八腿蛛;牢石犀/宽重紫牢石甲和晶角犀",
     "紫封狱主/巨紫封石门冠与双黑链臂的狱主;链渊狱兽/重紫岩甲和六条粗牢链的兽;石契封母/高紫多面石冠和多条紫符臂"),
    ("焚堂", "灰耳鼠/焦灰纸耳的小鼠;烬羽雀/灰白焦羽和烬腹雀;焚页狐/卷焦灰页长尾狐;焦架蟹/宽黑木焦架甲蟹;焚纸童/烧卷纸帽和焦木腿童;灰页獾/灰白焚页胖肚獾;烬瓮蛙/焦黑陶瓮身蛙;焦梁守/高焦木梁甲和双黑钳守卫;焚卷蛇/烧卷黑白愿页组成的蛇;灰芯蜂/薄焦页翼的小蜂;焦纸蛛/黑灰纸网腹和焦木八腿蛛;焚架犀/宽烧黑档架甲和焦书角犀",
     "灰愿堂主/巨大焚页纸冠与两条焦梁臂的堂主;焦藏镇兽/重黑档架甲和焦骨爪的兽;残签灰后/高卷焦纸裙与灰白签条臂的后"),
    ("悬阁", "绳耳鼠/麻绳耳和木尾小鼠;云帆雀/浅蓝云帆翼雀;索尾狐/三条麻索尾的狐;浮台蟹/宽浮木台甲蟹;绳帽童/细麻帽和悬木腿童;云筐獾/浅木筐胖腹獾;绳瓮蛙/麻绳结瓮身蛙;悬梁守/高白木悬梁甲守卫;索结蛇/长麻索和白木节组成的蛇;云翼蜂/小浅蓝云纸翼蜂;结索蛛/编绳腹和悬索八腿蛛;悬台犀/宽白木浮台甲与粗绳角犀",
     "云索阁主/巨悬木台冠与双麻索操杆臂;浮楼镇兽/大白木浮楼甲和云纸翼的兽;万索织后/高编绳罩裙和六条悬索长臂"),
    ("陵园", "碑耳鼠/小青灰碑耳鼠;月羽雀/冷灰蓝羽翼雀;墓苔狐/三条低苔石尾狐;月碑蟹/宽青灰墓碑甲蟹;无名童/细空白碑帽和冷灰纸童;青墓獾/圆苔墓石胖肚獾;月瓮蛙/低青灰石瓮蛙;残碑守/高破月碑甲守卫;碑节蛇/串联小空白青碑的蛇;月翅蜂/小银灰月纸翼蜂;柏根蛛/细柏根八腿和苔腹蛛;墓台犀/宽青灰墓台甲和石月角犀",
     "无名陵主/巨大空白青灰碑冠和柏根臂的陵主;月墓镇兽/青苔重墓甲和冷月石爪的兽;柏影碑母/高银灰柏枝冠与多条空白碑臂"),
    ("判殿", "印耳鼠/小金印耳的赤木鼠;判羽雀/铜金封羽雀;朱印狐/三条深红封签尾狐;秤盘蟹/大铜秤盘壳蟹;判签童/长朱木签帽和金铜衣童;印匣獾/大方朱印匣胖肚獾;金印蛙/铜金判瓮肚蛙;殿柱守/高红漆宫柱甲护卫;判链蛇/铜判链和深红签节蛇;金签蜂/薄判签翼小蜂;秤丝蛛/铜秤网腹和金链八腿蛛;判台犀/宽深红判台甲和金印角犀",
     "铜秤殿卫/巨大铜秤双盾与深红柱甲的殿卫;朱印镇将/巨方朱印腹和铜判锤双臂的镇将"),
    ("天穹", "星耳鼠/小金星耳的紫纸鼠;愿羽雀/薄紫愿页羽翼雀;星线狐/三条金星线尾狐;愿页蟹/宽折愿页星甲蟹;星签童/细紫星签帽和浮纸腿童;星匣獾/圆紫星图匣胖肚獾;月页蛙/折金月愿页肚蛙;天弧守/高铜天球弧甲护卫;星页蛇/串联紫金星页的长蛇;星灯蜂/细金星光翼小蜂;星线蛛/铜星盘腹和金丝八腿蛛;愿台犀/宽紫星图浮台甲和金月角犀",
     "星图巡首/巨金星图冠与紫愿页披风的巡首;愿海天兽/巨大紫愿页甲与铜天球环的兽;金弧织母/多条铜天弧臂与金星线裙的织母;虚页月后/银紫月环冠与六条浮愿页臂的后;星灯巨蟹/宽紫星图甲壳与双金星灯爪;悬愿总使/高铜星球架和多层紫愿页披衣的使"),
]

# English silhouettes supplement the named, map-specific physical components above.
SHAPES = ["tiny low four-legged rodent", "tiny folded winged bird", "slim long-tailed fox", "wide low crab with six legs",
          "tall slender two-legged puppet", "fat squat badger", "wide squat frog", "very tall broad armored guard",
          "long curved segmented serpent", "very small two-winged bee", "wide eight-legged spider", "massive low heavy rhinoceros"]
MOVEMENTS = ["chase", "hop", "strafe", "anchor", "retreat", "bounce", "sine", "chase", "sine", "orbit", "retreat", "chase"]
RADII = [10, 11, 14, 23, 16, 24, 19, 28, 16, 9, 22, 32]
SPEEDS = [119, 132, 114, 42, 85, 63, 91, 57, 100, 149, 76, 64]
ATTACKS = ["dart", "hop", "fan", "lob", "beam", "bounce", "triple", "melee", "snake", "orbit", "web", "charge"]
BOSS_PATTERNS = [
    [("procession", "lantern_rain", "ember"), ("strafe", "fan", "web"), ("orbit", "candle", "summon")],
    [("serpent", "flood", "snake"), ("procession", "pull", "wake"), ("strafe", "lane", "flood")],
    [("stomp", "coins", "grid"), ("bounce", "lob", "coins"), ("anchor", "cross", "pulse")],
    [("anchor", "roots", "petals"), ("pounce", "charge", "roots"), ("orbit", "petals", "summon")],
    [("strafe", "ink", "fan"), ("serpent", "snake", "ink"), ("anchor", "lane", "summon")],
    [("blink", "fan", "petals"), ("orbit", "web", "reflect"), ("procession", "summon", "lane")],
    [("strafe", "candle", "pulse"), ("stomp", "ember", "cross"), ("anchor", "pulse", "summon")],
    [("anchor", "cross", "grid"), ("pounce", "charge", "beam"), ("stomp", "pulse", "lane")],
    [("stomp", "ember", "lob"), ("pounce", "charge", "candle"), ("anchor", "rain", "pulse")],
    [("orbit", "petals", "flood"), ("bounce", "pulse", "wake"), ("strafe", "reflect", "petals")],
    [("serpent", "snake", "web"), ("pounce", "charge", "reflect"), ("blink", "fan", "lane")],
    [("stomp", "pulse", "cross"), ("bounce", "coins", "lob"), ("procession", "lane", "grid")],
    [("anchor", "roots", "fan"), ("pounce", "charge", "cross"), ("orbit", "web", "petals")],
    [("blink", "reflect", "cross"), ("serpent", "snake", "reflect"), ("strafe", "beam", "fan")],
    [("anchor", "grid", "web"), ("pounce", "charge", "pull"), ("procession", "judgment", "cross")],
    [("stomp", "rain", "ember"), ("pounce", "charge", "ink"), ("strafe", "fan", "candle")],
    [("orbit", "web", "spiral"), ("bounce", "cross", "lane"), ("procession", "pull", "fan")],
    [("anchor", "roots", "summon"), ("stomp", "pulse", "petals"), ("blink", "reflect", "ink")],
    [("procession", "judgment", "cross"), ("stomp", "grid", "coins")],
    [("orbit", "spiral", "lane"), ("serpent", "snake", "ledger"), ("anchor", "web", "grid"),
     ("blink", "reflect", "petals"), ("strafe", "coins", "candle"), ("procession", "judgment", "summon")],
]


def build_encounters():
    enemies, bosses, pools = [], [], []
    for index, (prefix, small, large) in enumerate(FAMILIES):
        theme = THEMES[index]
        mid = f"m{index+1:02}"
        colour = f"{theme['environment']}. Incorporate {theme['architecture']}; handmade coloured paper, wood and fabric matching this environment."
        mobs = []
        for j, entry in enumerate(small.split(";")):
            name, feature = entry.split("/")
            identity = f"e{57+index*12+j:02}"
            mobs.append(identity)
            radius = RADII[j]
            enemies.append(dict(id=identity, name=name, theme=mid, floor=1, health=26+radius*2,
                speed=SPEEDS[j], radius=radius, render_size=66+radius*2, damage=1, telegraph_ms=650+j%3*100,
                pattern=ATTACKS[j], movement=MOVEMENTS[j], can_mark=True, natural_ash=8, reward_once=True,
                counterplay="辨认本层轮廓；绕开预告后还击", art_brief=f"{SHAPES[j]}; {feature}; {colour}"))
        boss_ids = []
        for j, entry in enumerate(large.split(";")):
            name, feature = entry.split("/")
            identity = f"b{38+len(bosses):02}"
            move, attack, secondary = BOSS_PATTERNS[index][j]
            boss_ids.append(identity)
            bosses.append(dict(id=identity, name=name, theme=mid, floor=1, health=1180+j*130,
                optional=True, fixed_heal_phase_indices=[1], natural_ash=30, movement=move,
                attack_family=attack, secondary_family=secondary, size=228+j%3*22, radius=36+j%3*4, speed=55+j%3*10,
                phases=[f"{attack}：明确前摇与留空", f"{secondary}：位移后施法", "两种招式交错；保留恢复窗口"],
                window="施法后0.8秒", unlock_condition="所属环境的主线与双首领房",
                art_brief=f"colossal unique folklore paper boss, {feature}; distinct complete silhouette, no miniature extras; {colour}"))
        if index == 18: boss_ids.insert(0, "b36")
        if index == 19: boss_ids.insert(0, "b37")
        pools.append(dict(id=mid, enemy_ids=mobs, boss_ids=boss_ids, random_boss_ids=[b for b in boss_ids if b not in ["b36", "b37"]]))
    return enemies, bosses, pools
