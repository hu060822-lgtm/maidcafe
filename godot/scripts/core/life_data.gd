## Living Hearts content: what each character likes, how they spend days off, what they ask the manager for,
## their personal stories, customers' life changes and seasonal decorations. Pure data (original content).
##
## Like/dislike tags are checked by life.gd against what really happened today:
##   music:<key> light:<key> weather:<key> act:<activity> furn:<furniture type> style:<style> decor
##   busy (many customers) quiet (few customers) dish:<id> (on today's menu)
extends RefCounted

const MAID_LIFE := {
	"koharu": {
		"likes": ["music:pop", "act:costume", "act:stage", "busy", "furn:plush", "furn:photo", "decor"],
		"dislikes": ["quiet", "light:dim"],
		"hobby": "跟著偶像影片練舞、想新的招呼台詞",
		"offday": {"plaza": "她跟著廣場的音樂輕輕哼歌。", "sweets": "她在糖霜屋的櫥窗前看新出的蛋糕看到入迷。"},
		"wants": [
			{"kind": "furniture", "type": "plush", "ask": "店長～店裡如果有一隻大熊熊，客人一進門就會笑出來喔！", "promise": "在店裡擺一隻大型絨毛熊"},
			{"kind": "activity", "act": "costume", "ask": "下次可以辦主題服裝日嗎？我已經想好要穿什麼了！", "promise": "這幾天辦一次主題服裝日"},
			{"kind": "music", "key": "pop", "ask": "營業的時候……可以放偶像流行歌嗎？我會更有精神！", "promise": "找一天營業時放偶像流行歌"},
		],
		"arc": [
			{"need": {"bond": 45, "days_worked": 5}, "title": "小春的歌詞本", "lines": ["打烊後，小春從包包裡拿出一本畫滿星星的筆記本。", "小春：「這是……我寫的歌詞。很好笑對吧？」", "小春：「我一直想站在舞台上唱給大家聽。就算只有一首也好。」"],
				"choices": [
					{"label": "「店裡有舞台的那天，第一首就給妳唱。」", "fx": {"bond": 8, "mood": 10, "promise": {"kind": "furniture", "type": "stage", "days": 14, "text": "在店裡擺一座小舞台，讓小春唱歌"}, "memory": ["店長答應過，有舞台的那天讓我唱第一首歌。", 3.0]}},
					{"label": "「先把接待練好再說吧。」", "fx": {"bond": -3, "mood": -4, "memory": ["給店長看了歌詞本……好像太早了。", 1.5]}},
				]},
			{"need": {"furn": "stage", "flag": "stage_days", "skill": ["performance", 60]}, "title": "第一首自己的歌", "lines": ["舞台的燈關掉以後，小春還站在上面。", "小春：「店長！今天唱的那首……是我寫的那首喔。有人跟著打拍子了！」", "她抱著歌詞本，眼淚和笑容混在一起。"],
				"choices": [{"label": "「那是妳的歌。以後也唱給大家聽吧。」", "fx": {"bond": 6, "mood": 15, "exp": ["performance", 30], "album": ["小春的第一首歌", "小春在小舞台上唱了自己寫的歌。歌詞本的第一頁，多了一行字：「第一次被聽見的日子」。"]}}]},
		],
	},
	"rin": {
		"likes": ["music:jazz", "light:dim", "busy", "furn:gramophone", "dish:sig_pudding", "dish:sp_omurice"],
		"dislikes": ["furn:plush", "act:costume"],
		"hobby": "研究醬汁的比例、磨刀",
		"offday": {"grocer": "她認真地比較著兩顆蛋，山田大叔在旁邊笑。", "general": "她站在咖啡豆的貨架前聞了很久。"},
		"wants": [
			{"kind": "dish", "dish": "m_napolitan", "ask": "……拿坡里義大利麵，我改良了配方。可以放上菜單嗎？", "promise": "把拿坡里義大利麵放上菜單"},
			{"kind": "upgrade", "id": "second_stove", "ask": "一台爐子不夠。……我知道很貴，但我想要第二台。", "promise": "買第二台爐具"},
			{"kind": "music", "key": "jazz", "ask": "……爵士樂。做菜的時候，節奏比較穩。", "promise": "找一天營業時放爵士樂"},
		],
		"arc": [
			{"need": {"bond": 45, "skill": ["cooking", 72]}, "title": "料理比賽的傳單", "lines": ["凜把一張傳單壓在收銀台下面，假裝沒有這回事。", "傳單上寫著：「商店街料理大賽．三天後」。", "凜：「……我只是看看而已。店裡那天也需要人。」"],
				"choices": [
					{"label": "「那天放假，去比賽吧。」", "fx": {"bond": 8, "mood": 8, "promise": {"kind": "dayoff_on", "days": 3, "text": "比賽那天讓凜放假", "kept_flag": "rin_contest_went"}, "flag": "rin_contest_planned", "memory": ["店長叫我去比賽。……不能丟臉。", 3.0]}},
					{"label": "「店裡少不了妳。」", "fx": {"bond": -6, "mood": -6, "memory": ["沒去成的料理比賽。", 2.5]}},
				]},
			{"need": {"flag": "rin_contest_went"}, "title": "凜的獎狀", "lines": ["凜一早就把一張獎狀放在廚房的櫃子上，什麼都沒說。", "獎狀上寫著「商店街料理大賽．優秀賞」。", "凜：「……第二名。下次會是第一。」她的嘴角明顯在上揚。"],
				"choices": [{"label": "把獎狀裱框，掛在店裡", "fx": {"bond": 5, "mood": 15, "exp": ["cooking", 40], "album": ["凜的獎狀", "凜在商店街料理大賽拿到了優秀賞。獎狀被掛在廚房門口，她每天經過都會偷看一眼。"]}}]},
		],
	},
	"shizuku": {
		"likes": ["quiet", "weather:rain", "furn:plant", "furn:vase", "music:classical", "light:warm"],
		"dislikes": ["busy", "act:stage", "music:pop"],
		"hobby": "照顧植物、寫信給老家",
		"offday": {"park": "她坐在長椅上寫信，信紙上畫著小花。", "general": "她在月光雜貨挑了很久的信紙。"},
		"wants": [
			{"kind": "furniture", "type": "plant", "ask": "那、那個……店裡可以再多一盆植物嗎？看到綠色的東西，我會比較不緊張……", "promise": "在店裡多擺一盆盆栽"},
			{"kind": "music", "key": "classical", "ask": "如果放古典樂……我、我可能比較不會手抖……", "promise": "找一天營業時放古典樂"},
		],
		"arc": [
			{"need": {"bond": 40, "days_worked": 6}, "title": "老家的來信", "lines": ["雫收到了一封從老家寄來的信。", "雫：「媽媽問我……在城市過得好不好。我、我不知道要怎麼回。」", "雫：「如果能寄一張店裡的照片給她……她應該會放心吧。」"],
				"choices": [
					{"label": "「我會在店裡擺一個拍照區，大家一起拍。」", "fx": {"bond": 8, "mood": 6, "promise": {"kind": "furniture", "type": "photo", "days": 10, "text": "擺一個拍照區，讓雫拍照寄回家", "kept_flag": "shizuku_photo"}, "memory": ["店長說要一起拍照寄回家。", 3.0]}},
					{"label": "「用妳自己的話寫就好。」", "fx": {"bond": 3, "mood": 2, "end_arc": true, "memory": ["自己寫了回信給媽媽。寫了三張才寫好。", 2.0]}},
				]},
			{"need": {"flag": "shizuku_photo", "greets_done": 25}, "title": "回信", "lines": ["老家又寄來了一封信，裡面夾著一張剪下來的照片——是雫寄回去的那張。", "「照片裡的妳在笑。媽媽好久沒看到妳這樣笑了。」", "雫把信讀了一遍又一遍，然後小聲說：「……明天，我想試著自己帶位。」"],
				"choices": [{"label": "「我會在旁邊看著。」", "fx": {"bond": 6, "mood": 15, "exp": ["reception", 40], "album": ["寄回家的照片", "雫把店裡的照片寄回老家。媽媽的回信裡寫著：「照片裡的妳在笑。」"]}}]},
		],
	},
	"yukino": {
		"likes": ["quiet", "furn:bookshelf", "music:classical", "weather:rain", "weather:snow", "light:dim"],
		"dislikes": ["act:stage", "busy"],
		"hobby": "讀書、偷偷寫短篇小說",
		"offday": {"general": "她正在翻舊書，手邊已經疊了三本。", "park": "她在樹蔭下的長椅讀書，連鴿子靠近都沒發現。"},
		"wants": [
			{"kind": "furniture", "type": "bookshelf", "ask": "店裡如果有一座書架……客人和我們，都能有個安靜的角落。", "promise": "在店裡擺一座書架"},
			{"kind": "music", "key": "classical", "ask": "下雨的晚上，配古典樂應該很好。", "promise": "找一天營業時放古典樂"},
		],
		"arc": [
			{"need": {"bond": 45, "days_worked": 8}, "title": "雪乃的稿紙", "lines": ["打烊後，雪乃把一疊稿紙收進包包時，掉了一張。", "上面寫著：「在一間小小的咖啡廳裡，有一個總是不太笑的女孩——」", "雪乃：「……被看到了。我在寫小說。還沒給任何人看過。」"],
				"choices": [
					{"label": "「寫完的時候，可以讓我第一個讀嗎？」", "fx": {"bond": 8, "mood": 8, "flag": "yukino_writing", "memory": ["答應讓店長第一個讀我的小說。", 3.0]}},
					{"label": "（假裝沒看到，把稿紙還給她）", "fx": {"bond": 4, "mood": 2, "flag": "yukino_writing"}},
				]},
			{"need": {"flag": "yukino_writing", "customer_visits": ["amamiya", 4]}, "title": "兩個寫故事的人", "lines": ["雨宮先生結帳時，看見雪乃放在櫃台邊的稿紙。", "雨宮：「……這段寫得很好。人物的沉默，比台詞更有聲音。」", "雪乃愣了很久，然後深深地鞠了一個躬。"],
				"choices": [{"label": "（在旁邊替她高興）", "fx": {"bond": 5, "mood": 15, "album": ["兩個寫故事的人", "雨宮先生讀了雪乃的小說。「人物的沉默，比台詞更有聲音。」雪乃說，那是她收過最好的禮物。"]}}]},
		],
	},
	"kaede": {
		"likes": ["busy", "act:stage", "act:meetup", "weather:sunny", "music:pop"],
		"dislikes": ["quiet", "weather:rain", "light:dim"],
		"hobby": "晨跑、和人比賽",
		"offday": {"park": "她在公園跑步道上一圈一圈地跑。", "plaza": "她在廣場跟小學生比賽跑步，還故意輸了一次。"},
		"wants": [
			{"kind": "activity", "act": "meetup", "ask": "店長！辦熟客交流會嘛！大家一起熱鬧一下！", "promise": "這幾天辦一次熟客交流會"},
			{"kind": "furniture", "type": "stage", "ask": "如果有舞台，我可以表演翻跟斗喔！……開玩笑的，一半啦。", "promise": "在店裡擺一座小舞台"},
		],
		"arc": [
			{"need": {"bond": 40, "days_worked": 5}, "title": "商店街路跑", "lines": ["楓把一張報名表拍在桌上。", "楓：「這個星期天，商店街有路跑！我以前是田徑隊的，一定要跑！」", "楓：「……但是那天店裡很忙吧。」她的聲音突然小了下來。"],
				"choices": [
					{"label": "「那天放假，去跑吧！」", "fx": {"bond": 8, "mood": 10, "promise": {"kind": "dayoff_on", "weekday": 6, "text": "星期天讓楓放假去路跑", "kept_flag": "kaede_race_went"}, "flag": "kaede_race_planned", "memory": ["店長讓我去跑路跑！", 3.0]}},
					{"label": "「下次吧，這週人手不夠。」", "fx": {"bond": -5, "mood": -8, "memory": ["沒能去跑的路跑。", 2.5]}},
				]},
			{"need": {"flag": "kaede_race_went"}, "title": "終點線", "lines": ["楓脖子上掛著一面獎牌衝進店裡。", "楓：「第三名！最後一百公尺被追過去了啦——可是好開心！」", "她把獎牌掛在休息室的鏡子上，說要每天看一次。"],
				"choices": [{"label": "「下次一定拿第一。」", "fx": {"bond": 5, "mood": 15, "exp": ["floor", 30], "album": ["楓的獎牌", "楓在商店街路跑拿到第三名。獎牌掛在休息室的鏡子上，她說這是「下次的動力」。"]}}]},
		],
	},
	"tsumugi": {
		"likes": ["quiet", "furn:sofa_table", "furn:plush", "light:warm", "style:warm", "decor"],
		"dislikes": ["busy", "act:stage"],
		"hobby": "縫紉、做椅墊和小布偶",
		"offday": {"general": "她和月見小姐一起挑毛線，兩個人都笑得很開心。", "park": "她坐在長椅上織圍巾，旁邊坐著一隻貓。"},
		"wants": [
			{"kind": "furniture", "type": "sofa_table", "ask": "我做了幾個椅墊……如果店裡有沙發座，就能放上去了。", "promise": "在店裡擺一組沙發座"},
			{"kind": "decor", "ask": "季節換了，店裡也換個裝飾好不好？我可以幫忙做。", "promise": "掛上這一季的季節裝飾"},
		],
		"arc": [
			{"need": {"bond": 42, "days_worked": 4}, "title": "紬的針線盒", "lines": ["休息室裡，紬把一個舊針線盒放在膝上。", "紬：「這是奶奶留給我的。她以前開過一間小小的裁縫店。」", "紬：「我想……在這間店裡，也留下一點我做的東西。」"],
				"choices": [
					{"label": "「店裡的椅墊，就交給妳了。」", "fx": {"bond": 8, "mood": 10, "flag": "tsumugi_cushions", "memory": ["店長讓我替店裡做椅墊。", 3.0]}},
					{"label": "「好好休息，別太累了。」", "fx": {"bond": 3, "mood": 3}},
				]},
			{"need": {"flag": "tsumugi_cushions", "furn": "sofa_table", "days_worked": 10}, "title": "手縫的椅墊", "lines": ["沙發座上多了幾個手縫的椅墊，每一個的花樣都不一樣。", "春日太太摸著椅墊說：「這是誰做的？好像我年輕時用的那種。」", "紬躲在櫃台後面，耳朵紅了。"],
				"choices": [{"label": "「是我們店的紬做的。」", "fx": {"bond": 5, "mood": 15, "album": ["手縫的椅墊", "紬替沙發座縫了椅墊。客人問是誰做的，她躲在櫃台後面紅了耳朵。"]}}]},
		],
	},
	"chinatsu": {
		"likes": ["music:classical", "music:pop", "act:street_music", "act:stage", "furn:gramophone", "furn:stage"],
		"dislikes": ["music:none", "busy"],
		"hobby": "練吉他、在筆記本上寫旋律",
		"offday": {"plaza": "她坐在奏旁邊，抱著吉他練和弦。", "park": "她對著池塘小聲地唱歌，被鴿子圍住了。"},
		"wants": [
			{"kind": "music", "key": "classical", "ask": "那個……今天可以放古典樂嗎？我想聽聽看客人喜不喜歡。", "promise": "找一天營業時放古典樂"},
			{"kind": "furniture", "type": "gramophone", "ask": "如果店裡有一台留聲機……打烊後我想聽黑膠唱片。", "promise": "在店裡擺一台古董留聲機"},
		],
		"arc": [
			{"need": {"bond": 42, "days_worked": 4}, "title": "奏的學妹", "lines": ["千夏抱著吉他盒，在休息室門口站了好久。", "千夏：「奏學姊說……一直在廣場唱歌，聽眾只有路過的人。」", "千夏：「我想和學姊在這間店裡，好好唱完一整首歌。」"],
				"choices": [
					{"label": "「找一天，我們辦一場音樂之夜。」", "fx": {"bond": 8, "mood": 10, "promise": {"kind": "activity", "act": "street_music", "days": 10, "text": "辦一場街頭音樂之夜，讓千夏和奏一起唱", "kept_flag": "chinatsu_sang"}, "memory": ["店長說要辦音樂之夜。", 3.0]}},
					{"label": "「先在店裡練習吧。」", "fx": {"bond": 2, "mood": 0}},
				]},
			{"need": {"flag": "chinatsu_sang"}, "title": "二重唱", "lines": ["打烊後，千夏的手還在發抖。", "千夏：「學姊說……我今天的和聲，是她聽過最好聽的。」", "窗外，奏揹著吉他朝店裡揮了揮手。"],
				"choices": [{"label": "「下次也一起唱吧。」", "fx": {"bond": 5, "mood": 15, "exp": ["performance", 35], "album": ["二重唱", "千夏和奏在店裡唱完了一整首歌。那天，沒有一位客人提早離開。"]}}]},
		],
	},
	"aoi": {
		"likes": ["busy", "music:jazz", "light:bright", "style:elegant", "dish:d_coffee", "furn:display"],
		"dislikes": ["light:dim", "quiet"],
		"hobby": "研究咖啡豆、拉花",
		"offday": {"general": "她在咖啡豆的貨架前一包一包地聞，月見小姐在旁邊做筆記。", "plaza": "她去連鎖咖啡店排隊，回來時表情很複雜。"},
		"wants": [
			{"kind": "upgrade", "id": "coffee_machine", "ask": "這台咖啡機……我在前一家店用過更好的。如果有義式咖啡機，我可以做拉花。", "promise": "買一台義式咖啡機"},
			{"kind": "dish", "dish": "d_coffee", "ask": "手沖咖啡請一定要留在菜單上。那是一間店的臉。", "promise": "把手沖咖啡放上菜單"},
		],
		"arc": [
			{"need": {"bond": 42, "days_worked": 4}, "title": "連鎖店的制服", "lines": ["葵把一件連鎖咖啡店的制服摺好，放進紙袋。", "葵：「在那裡，每一杯都一樣。快、準、一樣。」", "葵：「我想做的是……讓客人記得是誰泡的咖啡。」"],
				"choices": [
					{"label": "「那就讓客人記住妳的咖啡。」", "fx": {"bond": 8, "mood": 10, "flag": "aoi_latte", "memory": ["店長說，讓客人記住我的咖啡。", 3.0]}},
					{"label": "「規矩還是要守的。」", "fx": {"bond": -2, "mood": -3}},
				]},
			{"need": {"flag": "aoi_latte", "upgrade": "coffee_machine", "skill": ["cooking", 55]}, "title": "第一個拉花", "lines": ["葵端出一杯咖啡，奶泡上浮著一隻小小的兔子。", "早瀨先生盯著杯子看了好久：「……這捨不得喝啊。」", "葵轉過身去，偷偷比了一個勝利手勢。"],
				"choices": [{"label": "（替她拍下那杯咖啡）", "fx": {"bond": 5, "mood": 15, "album": ["兔子拉花", "葵做出了第一個拉花。早瀨先生說捨不得喝，最後還是喝了，然後又點了一杯。"]}}]},
		],
	},
	"hiyori": {
		"likes": ["weather:sunny", "quiet", "furn:sofa_table", "furn:plant", "light:warm", "furn:plush"],
		"dislikes": ["busy", "weather:hot"],
		"hobby": "午睡、照顧公園的花圃",
		"offday": {"park": "她在花圃旁邊幫忙澆水，然後在樹下睡著了。", "grocer": "她和山田大叔聊天氣，聊了一個小時。"},
		"wants": [
			{"kind": "furniture", "type": "plant", "ask": "店裡再多一點綠色好不好～植物會讓時間變慢喔。", "promise": "在店裡多擺一盆盆栽"},
			{"kind": "furniture", "type": "sofa_table", "ask": "沙發……是人類最偉大的發明……店裡有一組就好了……", "promise": "在店裡擺一組沙發座"},
		],
		"arc": [
			{"need": {"bond": 40, "days_worked": 5}, "title": "日和的花圃", "lines": ["日和帶了一包種子來店裡。", "日和：「公園的花圃要整修，管理員爺爺說這些花沒地方種了。」", "日和：「店門口……可以借我一個小角落嗎？」"],
				"choices": [
					{"label": "「店裡多擺幾盆，交給妳照顧。」", "fx": {"bond": 8, "mood": 10, "promise": {"kind": "furniture", "type": "plant", "count": 2, "days": 8, "text": "店裡擺兩盆以上的盆栽，讓日和照顧", "kept_flag": "hiyori_garden"}, "memory": ["店長讓我在店裡種花。", 3.0]}},
					{"label": "「我們店沒地方啊。」", "fx": {"bond": -4, "mood": -5, "memory": ["那包種子，後來送給公園的爺爺了。", 2.0]}},
				]},
			{"need": {"flag": "hiyori_garden", "days_worked": 10}, "title": "開花了", "lines": ["早上開店前，日和把大家叫到窗邊。", "日和：「你們看——開花了。」", "淡黃色的小花，在窗台的盆栽裡開了三朵。"],
				"choices": [{"label": "（和大家一起看花）", "fx": {"bond": 5, "mood": 15, "album": ["窗台的小花", "日和種的花開了。大家擠在窗邊看了好久，誰都沒有說話。"]}}]},
		],
	},
}

## Joint events between two maids; triggered from their directional relationship (see life.gd pair_events).
const PAIR_EVENTS := {
	"mentor": {"title": "%s的小老師", "lines": ["打烊後，%s叫住了%s。", "%s：「剛剛那個，我教妳一個訣竅。」", "%s學得很認真，連筆記都拿出來了。"]},
	"rival": {"title": "%s和%s的比賽", "lines": ["%s：「今天誰送得比較多？」", "%s：「當然是我。明天再比一次。」", "兩個人嘴上不饒人，手上的動作卻越來越默契。"]},
	"reconcile": {"title": "和好", "lines": ["%s端著兩杯熱可可走到%s旁邊。", "%s：「……那天，是我說得太過分了。」", "%s接過杯子，小聲地說：「我也是。」"]},
	"dayoff": {"title": "%s和%s的休假日", "lines": ["%s和%s同一天放假，約好了一起出門。", "%s", "隔天，她們的手機桌布換成了同一張照片。"]},
}

## Customers' life changes: each stage needs real conditions, changes their routine (life state) and may tell a scene.
## life: {state, days(-1 = permanent), note, arrival:[t0,t1], weekdays:[...], chance:mul, absent:true}
const CUSTOMER_LIFE := {
	"kenta": [
		{"need": {"visits": 4}, "life": {"state": "job_hunting", "days": 7, "note": "在找工作。最近都穿著不合身的西裝，來得比較晚", "arrival": [130, 200], "chance": 0.85},
			"title": "健太的西裝", "lines": ["健太今天穿著西裝來店裡，領帶歪了一邊。", "健太：「我開始找工作了……面試好可怕。」", "他點了一份蛋包飯，吃得特別慢。"]},
		{"need": {"life_done": true}, "life": {"state": "employed", "days": -1, "note": "找到工作了。星期五下班後一定會來", "arrival": [40, 120], "weekdays": [4]},
			"title": "健太找到工作了", "lines": ["健太衝進店裡，手上揮著一張紙。", "健太：「錄取了！！我說面試前都會來這裡吃蛋包飯，面試官還笑了！」", "以後他會在星期五下班後來。"],
			"low_lines": ["健太找到工作了。他在帳單背面寫了一行「謝謝這段時間的照顧」。"], "album_if": 3, "album": "健太找到工作了"},
	],
	"misaki": [
		{"need": {"visits": 3, "furn": "photo"}, "life": {"state": "contest", "days": 6, "note": "在準備攝影比賽，常在拍照區待很久", "chance": 1.3},
			"title": "美咲的相機", "lines": ["美咲在拍照區前蹲了好久，換了好幾個角度。", "美咲：「我要參加攝影比賽！主題是『街角的溫度』……我想拍這間店。」"]},
		{"need": {"life_done": true}, "life": {"state": "", "days": -1, "note": ""},
			"title": "街角的溫度", "lines": ["美咲把一份雜誌攤在櫃台上。佳作那一頁，是店裡拍照區的照片。", "美咲：「得獎了！評審說，照片裡有人在笑的感覺。」"],
			"low_lines": ["美咲的攝影比賽結束了。她說沒得獎，但照片會一直留著。"], "album_if": 2, "album": "街角的溫度"},
	],
	"hayase": [
		{"need": {"visits": 4}, "life": {"state": "deadline", "days": 4, "note": "專案在趕截止日，這幾天不會來", "absent": true},
			"title": "早瀨先生的截止日", "lines": ["早瀨先生結帳時嘆了一口氣：「接下來幾天要閉關趕案子了。」", "早瀨：「……窗邊那個位子，幫我留著喔。開玩笑的。」"]},
		{"need": {"life_done": true}, "life": {"state": "", "days": -1, "note": ""},
			"title": "交稿了", "lines": ["消失了幾天的早瀨先生出現在門口，黑眼圈很深，表情卻很輕鬆。", "早瀨：「交稿了。……老樣子，咖啡跟拿坡里。」"],
			"low_lines": ["早瀨先生趕完案子回來了。"], "album_if": 4, "album": "早瀨先生交稿了"},
	],
	"riku": [
		{"need": {"visits": 2, "year_day": 22}, "life": {"state": "birthday", "days": 1, "note": "今天生日！爺爺說要帶他來吃布丁", "chance": 3.0},
			"title": "小陸的生日", "lines": ["高木爺爺牽著小陸走進店裡，小陸頭上戴著紙做的王冠。", "高木：「今天是這孩子的生日。他說，生日就要吃這裡的布丁。」"],
			"needs_dish": "s_pudding", "album": "小陸的生日布丁", "repeat_yearly": true},
	],
}

## Seasonal decoration (bought in preparation; taken down when the season ends).
const DECOR := {
	"spring": {"name": "櫻花吊飾", "price": 500, "style": {"cute": 2, "warm": 1}, "color": "f8c0d0", "desc": "窗邊掛滿紙做的櫻花。"},
	"summer": {"name": "風鈴與竹簾", "price": 500, "style": {"warm": 1, "retro": 2}, "color": "80c8e8", "desc": "門口的風鈴叮叮作響。"},
	"autumn": {"name": "楓葉與南瓜燈", "price": 500, "style": {"warm": 2, "fantasy": 1}, "color": "e08040", "desc": "桌上擺著小南瓜燈。"},
	"winter": {"name": "星星燈串", "price": 500, "style": {"elegant": 1, "fantasy": 2}, "color": "f0e8a0", "desc": "天花板掛著一閃一閃的燈串。"},
}
