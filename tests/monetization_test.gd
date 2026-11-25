extends Node
## Purchases, ads and rewards against the simulated Google Play and AdMob backends.
##   godot --headless --path . res://tests/monetization_test.tscn
## The real save file is never touched (G.test_no_save); a "restart" re-reads the profile from its JSON.

const CATALOG := preload("res://scripts/catalog.gd")
const FakeBilling := preload("res://scripts/billing_fake.gd")
const FakeAds := preload("res://scripts/ads_fake.gd")

var fails := 0
var lines: PackedStringArray = []
var results: Array = []      # purchase_result signals: [pid, status]
var restores: Array = []

func ok(cond: bool, name: String, info := "") -> void:
	var s := ("PASS  " if cond else "FAIL  ") + name + ("" if info == "" else "  (" + info + ")")
	print(s)
	lines.append(s)
	if not cond:
		fails += 1

func wait(t := 0.3) -> void:
	await get_tree().create_timer(t).timeout

func fresh_profile() -> void:
	G.test_no_save = true
	G.apply_data(G.migrate({"v": 4, "settings": {"lang": "en"}, "meta": {"crystals": 0}, "cos": {}, "ent": {}, "purchases": {},
		"rewards": {}, "ads": {}, "levels": {}, "support": {}, "run": {}, "result": {}}))

func restart_profile() -> void:
	## Process restart: the profile is rebuilt from its saved JSON.
	var data := JSON.parse_string(JSON.stringify({"v": 4, "settings": G.settings, "meta": G.meta, "cos": G.cos, "ent": G.ent,
		"purchases": G.purchases, "rewards": G.rewards, "ads": G.ads, "levels": G.levels, "support": G.support, "run": G.run,
		"result": G.result}))
	G.apply_data(data)

func _ready() -> void:
	Store.purchase_result.connect(func(pid, st): results.append([pid, st]))
	Store.restore_result.connect(func(st, n): restores.append([st, n]))
	await billing_tests()
	await ads_tests()
	await reward_tests()
	admob_config_tests()
	print("MONETIZATION " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	var f := FileAccess.open("user://monetization_test.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	get_tree().quit(1 if fails > 0 else 0)

func new_store(fake: Node = null) -> Node:
	var b: Node = fake if fake else FakeBilling.new()
	Store.use_backend(b)
	Store.license_key = ""
	Store.launch_id = "launch-1"
	Store.clock_offset = 0
	Store._focused = true
	results.clear()
	restores.clear()
	return b

func refund_confirmed() -> void:
	## Google Play stops listing an item and keeps doing so: three complete answers, two app launches, over an hour.
	Store.restore()
	await wait(0.4)
	Store.launch_id = "launch-%d" % randi()
	Store.clock_offset += 1800
	Store.restore()
	await wait(0.4)
	Store.clock_offset += 1900
	Store.restore()
	await wait(0.4)

func last_status(pid: String) -> String:
	for i in range(results.size() - 1, -1, -1):
		if results[i][0] == pid:
			return results[i][1]
	return ""

# ---------------------------------------------------------------- billing

func billing_tests() -> void:
	fresh_profile()
	var fake: Node = new_store()
	Store.start()
	await wait()
	ok(Store.is_ready() and Store.price("db_no_ads") == "US$3.99", "connect and read prices from ProductDetails", Store.price("db_no_ads"))
	# unavailable product
	fake.unlisted["db_ball_frost"] = true
	Store.refresh_details()
	await wait()
	ok(Store.state("db_ball_frost") == "missing" and Store.price("db_ball_frost") == "", "a product Google Play does not return is shown as unavailable")
	ok(not Store.buy("db_ball_frost") or true, "buying an unavailable product")
	await wait()
	ok(last_status("db_ball_frost") == "unavailable" and not G.owns("ball", "frost"), "it reports 'unavailable' and grants nothing", last_status("db_ball_frost"))
	fake.unlisted.clear()
	Store.refresh_details()
	await wait()
	# a permanent skin, with a double tap
	var d0: int = fake.calls.details
	var started := Store.buy("db_ball_amber")
	var second := Store.buy("db_ball_amber")
	await wait(0.4)
	ok(started and not second and fake.calls.launch == 1, "double tap opens one Google Play window", "launches %d" % fake.calls.launch)
	ok(fake.calls.details > d0, "fresh product details are requested before the purchase window")
	await wait(0.3)
	ok(G.owns("ball", "amber") and last_status("db_ball_amber") == "granted", "PURCHASED grants the ball")
	var tok := ""
	for t in G.purchases:
		if G.purchases[t].pid == "db_ball_amber":
			tok = t
	ok(tok != "" and G.purchases[tok].acked and fake.account[tok].is_acknowledged, "permanent purchase acknowledged after delivery")
	# the same purchase reported again (repeated callback, restart): no second grant
	var n_before: int = G.cos.balls.size()
	Store._handle(fake.account[tok].duplicate(true), true)
	Store._handle(fake.account[tok].duplicate(true), false)
	ok(G.cos.balls.size() == n_before and fake.calls.ack == 1, "repeated events for one purchaseToken change nothing", "acks %d" % fake.calls.ack)
	# buying it again: already owned
	Store.buy("db_ball_amber")
	await wait()
	ok(last_status("db_ball_amber") == "already_owned", "buying an owned item says it is already owned")
	# cancel
	fake.next["db_cannon_bronze"] = "cancel"
	Store.buy("db_cannon_bronze")
	await wait(0.5)
	ok(last_status("db_cannon_bronze") == "cancelled" and not G.owns("cannon", "bronze") and Store.state("db_cannon_bronze") == "", "cancelled in the Google Play window: nothing granted, button free again")
	# error
	fake.next["db_cannon_bronze"] = "error"
	Store.buy("db_cannon_bronze")
	await wait(0.5)
	ok(last_status("db_cannon_bronze") == "error" and not G.owns("cannon", "bronze"), "an error in the purchase flow grants nothing")
	# pending, then completed while the app was in the background
	fake.next["db_cannon_obsidian"] = "pending"
	Store.buy("db_cannon_obsidian")
	await wait(0.5)
	ok(last_status("db_cannon_obsidian") == "pending" and Store.state("db_cannon_obsidian") == "pending" and not G.owns("cannon", "obsidian"), "PENDING shows waiting and grants nothing")
	fake.approve_pending()
	Store._notification(NOTIFICATION_APPLICATION_RESUMED)
	await wait(0.4)
	ok(G.owns("cannon", "obsidian") and Store.state("db_cannon_obsidian") == "", "the pending purchase is granted when the app comes back after payment")
	# pending that gets cancelled
	fake.next["db_cannon_bronze"] = "pending"
	Store.buy("db_cannon_bronze")
	await wait(0.4)
	fake.cancel_pending()
	Store._notification(NOTIFICATION_APPLICATION_RESUMED)
	await wait(0.4)
	ok(not G.owns("cannon", "bronze") and Store.state("db_cannon_bronze") == "", "a pending purchase cancelled in Google Play leaves nothing and frees the button")
	# interrupted acknowledgement: retried on the next start
	fake.fail_ack_once = true
	Store.buy("db_cannon_crystal")
	await wait(0.6)
	var tok2 := ""
	for t in G.purchases:
		if G.purchases[t].pid == "db_cannon_crystal":
			tok2 = t
	ok(G.owns("cannon", "crystal_engine") and tok2 != "" and not G.purchases[tok2].acked, "acknowledge failed: the item is delivered, the acknowledgement stays open")
	restart_profile()
	Store.conn = Store.Conn.OFF
	Store.start()
	await wait(0.6)
	ok(G.purchases[tok2].acked and fake.account[tok2].is_acknowledged, "the open acknowledgement is completed on the next start")
	# two support contributions of the same amount; one consume fails once
	var support0: int = G.support.count
	Store.buy("db_support_small")
	await wait(0.5)
	fake.fail_consume_once = true
	Store.buy("db_support_small")
	await wait(0.5)
	ok(int(G.support.count) == support0 + 2, "two contributions of the same amount are both recorded", "count %d" % G.support.count)
	var open := 0
	for t in fake.account:
		if fake.account[t].product_ids.has("db_support_small"):
			open += 1
	ok(open == 1, "the contribution whose consume failed is still open in Google Play", "open %d" % open)
	Store.restore()
	await wait(0.6)
	open = 0
	for t in fake.account:
		if fake.account[t].product_ids.has("db_support_small"):
			open += 1
	ok(open == 0 and int(G.support.count) == support0 + 2, "it is consumed on the next query without being recorded twice")
	# Ad-Free
	Store.buy("db_no_ads")
	await wait(0.6)
	ok(G.is_ad_free(), "Ad-Free purchase sets the entitlement")
	# reinstall: empty profile, same Google account
	var owned_before: Array = G.ent.products.duplicate()
	fresh_profile()
	ok(not G.is_ad_free() and not G.owns("ball", "amber"), "a reinstall starts with an empty profile")
	Store.conn = Store.Conn.OFF
	restores.clear()
	Store.restore()
	await wait(0.8)
	var all_back := true
	for pid in owned_before:
		all_back = all_back and G.ent.products.has(pid)
	ok(all_back and G.is_ad_free() and G.owns("ball", "amber") and G.owns("cannon", "obsidian") and G.owns("cannon", "crystal_engine"),
		"Restore Purchases brings back every permanent item for the same Google account", str(G.ent.products))
	ok(not restores.is_empty() and restores[-1][0] == "ok", "restore reports success", str(restores))
	ok(int(G.support.count) == 0, "support contributions are not 'restored' (they were already used)")
	# network error: the local entitlement stays (no confirmed absence)
	fake.network_ok = false
	Store.restore()
	await wait(0.4)
	ok(G.owns("ball", "amber") and G.is_ad_free() and restores[-1][0] == "error", "a network error keeps the local items and is reported as an error")
	fake.network_ok = true
	# refund confirmed by Google Play
	fake.refund("db_ball_amber")
	G.cos.ball = "amber"
	Store.restore()
	await wait(0.5)
	ok(G.owns("ball", "amber") and G.cos.ball == "amber" and G.ent.absent.has("db_ball_amber"),
		"one answer without the item does not withdraw it yet (kept, absence recorded)")
	await refund_confirmed()
	ok(not G.owns("ball", "amber") and G.cos.ball == "classic" and G.owns("cannon", "obsidian"), "a refund confirmed by Google Play removes only that item and resets the selection")
	# billing unavailable on the device
	var f2: Node = new_store()
	f2.available = false
	Store.start()
	await wait(0.3)
	ok(Store.conn == Store.Conn.UNAVAILABLE, "no Google Play billing on the device: shown as unavailable")
	Store.buy("db_ball_frost")
	await wait(0.3)
	ok(last_status("db_ball_frost") == "billing_unavailable", "buying then says Google Play billing is unavailable on the device", last_status("db_ball_frost"))
	await revocation_tests()
	await error_tests()
	await signature_tests()
	new_store()

func revocation_tests() -> void:
	## A paid item is never taken away because of one odd answer of Google Play.
	fresh_profile()
	var f: Node = new_store()
	Store.start()
	await wait()
	Store.buy("db_no_ads")
	await wait(0.4)
	Store.buy("db_ball_obsidian")
	await wait(0.4)
	ok(G.is_ad_free() and G.owns("ball", "obsidian"), "setup: Ad-Free and a ball bought")
	# an OK answer that has no purchase list at all
	f.answer_without_list = true
	restores.clear()
	Store.restore()
	await wait(0.4)
	ok(G.is_ad_free() and G.owns("ball", "obsidian") and G.ent.absent.is_empty() and restores[-1][0] == "error",
		"incomplete answer (no purchase list): nothing withdrawn, nothing recorded, restore says error", str(restores))
	f.answer_without_list = false
	# a stale Play cache that leaves out permanent items, many times within one launch and over hours
	f.hide_owned = true
	for i in 5:
		Store.clock_offset += 3600
		Store.restore()
		await wait(0.3)
	ok(G.is_ad_free() and G.owns("ball", "obsidian"), "5 answers without the items in ONE launch (5 h): kept")
	f.hide_owned = false
	Store.restore()
	await wait(0.3)
	ok(G.ent.absent.is_empty() and G.is_ad_free(), "listed again: the absence record is cleared")
	# two launches but within minutes: kept
	f.hide_owned = true
	Store.restore()
	await wait(0.3)
	Store.launch_id = "launch-2"
	Store.clock_offset += 600
	Store.restore()
	await wait(0.3)
	Store.restore()
	await wait(0.3)
	ok(G.is_ad_free() and G.owns("ball", "obsidian"), "3 answers from 2 launches but only 10 minutes: kept")
	restart_profile()   # the absence record survives a restart
	ok(G.ent.absent.has("db_no_ads") and int(G.ent.absent.db_no_ads.n) == 3, "absence record is saved with the profile", str(G.ent.absent))
	Store.clock_offset += 3000
	Store.restore()
	await wait(0.3)
	ok(not G.is_ad_free() and not G.owns("ball", "obsidian"), "absent in 4 answers, 2 launches, over an hour: withdrawn")
	# it was a mistake after all: Google Play lists the purchases again → granted again, without a new payment
	f.hide_owned = false
	Store.restore()
	await wait(0.4)
	ok(G.is_ad_free() and G.owns("ball", "obsidian"), "items listed again by Google Play are granted again")
	# network errors never count as absence
	f.network_ok = false
	for i in 4:
		Store.launch_id = "launch-n%d" % i
		Store.clock_offset += 7200
		Store.restore()
		await wait(0.3)
	ok(G.is_ad_free() and G.ent.absent.is_empty(), "4 network errors over 8 h and 4 launches: nothing withdrawn, nothing recorded")
	f.network_ok = true
	# consumables are never 'withdrawn'; a refunded support purchase changes nothing
	var c0 := int(G.support.count)
	Store.buy("db_support_medium")
	await wait(0.4)
	f.refund("db_support_medium")
	await refund_confirmed()
	ok(int(G.support.count) == c0 + 1, "support purchases are not taken back")
	# old saves without the absence record load fine
	var old := {"v": 4, "settings": {"lang": "en"}, "meta": {"crystals": 1}, "cos": {}, "ent": {"no_ads": true, "products": ["db_no_ads"]},
		"purchases": {}, "rewards": {}, "ads": {}, "levels": {}, "support": {}, "run": {}, "result": {}}
	G.apply_data(G.migrate(old))
	ok(G.is_ad_free() and G.ent.absent is Dictionary and G.ent.absent.is_empty(), "a 1.2.1 save (no absence record) loads with Ad-Free kept")

func error_tests() -> void:
	## Each Google Play problem gets its own clear message; none of them grants anything.
	fresh_profile()
	var f: Node = new_store()
	Store.start()
	await wait()
	f.next["db_ball_amber"] = "network"
	Store.buy("db_ball_amber")
	await wait(0.4)
	ok(last_status("db_ball_amber") == "offline" and not G.owns("ball", "amber"), "network error in the Play window → 'no connection' message")
	f.next["db_ball_amber"] = "service"
	Store.buy("db_ball_amber")
	await wait(0.4)
	ok(last_status("db_ball_amber") == "offline", "service unavailable → 'no connection' message")
	f.launch_code = 3
	Store.buy("db_ball_amber")
	await wait(0.3)
	ok(last_status("db_ball_amber") == "billing_unavailable" and Store.state("db_ball_amber") == "", "billing unavailable when opening the window → own message, button free")
	f.launch_code = 12
	Store.buy("db_ball_amber")
	await wait(0.3)
	ok(last_status("db_ball_amber") == "offline", "network error when opening the window → 'no connection'")
	f.launch_code = 0
	f.network_ok = false
	Store.buy("db_ball_amber")
	await wait(0.4)
	ok(last_status("db_ball_amber") == "offline" and not G.owns("ball", "amber"), "no internet while fetching the offer → 'no connection'")
	f.network_ok = true
	Store._on_disconnected()
	ok(Store.conn == Store.Conn.ERROR, "disconnected: shown as not connected")
	Store.start()
	await wait(0.3)
	# the player takes a long time in the Google Play window: no false error
	f.next["db_cannon_bronze"] = "hold"
	Store.buy("db_cannon_bronze")
	await wait(0.3)
	Store._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Store.busy["db_cannon_bronze"].since -= 120000
	Store._process(0.0)
	ok(Store.busy.has("db_cannon_bronze") and last_status("db_cannon_bronze") == "", "2 minutes in the Play window: still waiting, no error shown")
	Store._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	Store._process(0.0)
	ok(Store.busy.has("db_cannon_bronze"), "back in the game: the answer gets the full time again")
	f.finish_held()
	await wait(0.4)
	ok(G.owns("cannon", "bronze") and last_status("db_cannon_bronze") == "granted", "the answer arrives: granted, no error was shown before")
	# no answer at all after returning: an error, and a late answer is still honoured once
	f.next["db_cannon_obsidian"] = "hold"
	Store.buy("db_cannon_obsidian")
	await wait(0.3)
	Store.busy["db_cannon_obsidian"].since -= 30000
	Store._process(0.0)
	ok(last_status("db_cannon_obsidian") == "error" and not Store.busy.has("db_cannon_obsidian"), "no answer 25 s after returning: error message, button free")
	f.finish_held()
	await wait(0.4)
	ok(G.owns("cannon", "obsidian") and last_status("db_cannon_obsidian") == "granted", "a late answer is still granted (once)")
	Store.restore()
	await wait(0.4)
	ok(G.ent.products.count("db_cannon_obsidian") == 1, "and not twice after the next query")
	# replay of a consumed support purchase (repeated callback, restart): counted once
	var c0 := int(G.support.count)
	Store.buy("db_support_large")
	await wait(0.5)
	var tok := ""
	for t in G.purchases:
		if G.purchases[t].pid == "db_support_large":
			tok = t
	var copy: Dictionary = {"purchase_token": tok, "package_name": "com.deepbounce.game", "purchase_state": 1,
		"product_ids": ["db_support_large"], "is_acknowledged": false, "original_json": "", "signature": ""}
	var consumes: int = f.calls.consume
	Store._handle(copy, true)
	restart_profile()
	Store._handle(copy, false)
	ok(int(G.support.count) == c0 + 1 and G.purchases[tok].consumed and f.calls.consume == consumes,
		"a consumed support purchase reported again (callback, restart) is not counted or consumed twice")
	# another app's purchase is ignored
	var other := copy.duplicate(true)
	other.purchase_token = "other-token"
	other.package_name = "com.example.other"
	Store._handle(other, true)
	ok(not G.purchases.has("other-token") and int(G.support.count) == c0 + 1, "a purchase for another package is ignored")
	# every status has a message in every language
	for st in ["purchase_error", "purchase_unverified", "store_offline", "billing_unavailable", "store_unavailable", "purchase_pending",
			"already_owned", "restore_error", "restored_none"]:
		var all := true
		for l in ["uk", "en", "pl", "de", "es", "fr", "it", "pt_BR", "tr", "ja", "ko", "zh_CN"]:
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://i18n/%s.json" % l))
			all = all and String(d.get(st, "")) != ""
		ok(all, "message '%s' exists in all 12 languages" % st)
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://i18n/en.json"))
	ok(not String(en.purchase_error).contains("not been charged"), "the general error no longer promises that nothing was charged")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	ok(main_src.contains('"offline"') and main_src.contains('"unverified"') and main_src.contains('"billing_unavailable"'),
		"the game shows a message for every purchase status")

# ---------------------------------------------------------------- ads

func ads_tests() -> void:
	fresh_profile()
	var fake: Node = FakeAds.new()
	Ads.use_backend(fake)
	Ads.start()
	await wait(0.2)
	ok(Ads.consent_done and Ads.can_request and Ads.privacy_required, "UMP consent result read at start (privacy entry required)")
	Ads.load_ad("revive")
	ok(Ads.status("revive") == "loading", "rewarded loading shows as loading")
	await wait(0.2)
	ok(Ads.status("revive") == "ready", "the button becomes active when the ad is ready")
	var earned: Array = []
	var closed: Array = []
	Ads.reward_earned.connect(func(p, a): earned.append([p, a]))
	Ads.rewarded_closed.connect(func(p, a, e, err): closed.append([p, a, e, err]))
	ok(Ads.show_rewarded("revive", "run-A"), "the player starts the rewarded ad")
	await wait(0.3)
	ok(earned.size() == 1 and G.reward_state("revive", "run-A") == "earned" and closed.size() == 1 and closed[0][2], "the reward is recorded when the SDK reports it, then the ad closes")
	# repeated reward callback
	fake.outcome = "double_cb"
	Ads.load_ad("double")
	await wait(0.2)
	Ads.show_rewarded("double", "run-B")
	await wait(0.3)
	var n_b := 0
	for e in earned:
		if e[1] == "run-B":
			n_b += 1
	ok(n_b == 1, "a repeated reward callback is ignored")
	# closed before the reward
	fake.outcome = "close"
	Ads.load_ad("double")
	await wait(0.2)
	Ads.show_rewarded("double", "run-C")
	await wait(0.3)
	ok(G.reward_state("double", "run-C") == "" and closed[-1][2] == false, "closing the video early gives no reward and returns to the choice")
	# failure to show
	fake.outcome = "fail"
	Ads.load_ad("revive")
	await wait(0.2)
	Ads.show_rewarded("revive", "run-D")
	await wait(0.3)
	ok(closed[-1][3] == "show_failed" and G.reward_state("revive", "run-D") == "", "an ad that fails to show returns control with an error")
	# no network
	fake.outcome = "reward"
	fake.network_ok = false
	Ads.load_ad("revive")
	await wait(0.3)
	ok(Ads.status("revive") == "unavailable" and not Ads.show_rewarded("revive", "run-E"), "no network: the video is unavailable and cannot be started")
	fake.network_ok = true
	# interstitial limits
	G.ads = {"finished_total": 0, "since_runs": 0, "since_secs": 0.0, "shown": 0}
	var due: Array = []
	for i in 3:
		G.ads.finished_total += 1
		G.ads.since_runs += 1
		G.ads.since_secs += 400.0
		due.append(Ads.interstitial_due(false))
	ok(due == [false, false, false], "the first three finished runs are free of interstitials")
	G.ads.finished_total += 1
	G.ads.since_runs += 1
	ok(Ads.interstitial_due(false), "the fourth finished run may show one (3 runs and 180 s since the start)")
	ok(not Ads.interstitial_due(true), "not after a run in which a rewarded ad was watched")
	Ads.load_ad("interstitial")
	await wait(0.2)
	var nexted := [false]
	Ads.show_interstitial_then(false, func(): nexted[0] = true)
	await wait(0.3)
	ok(nexted[0] and int(G.ads.shown) == 1 and int(G.ads.since_runs) == 0 and is_zero_approx(float(G.ads.since_secs)), "after the interstitial the next run starts and the counters reset")
	G.ads.finished_total += 2
	G.ads.since_runs = 2
	G.ads.since_secs = 900.0
	ok(not Ads.interstitial_due(false), "two runs later: not yet (needs three)")
	G.ads.since_runs = 3
	G.ads.since_secs = 120.0
	ok(not Ads.interstitial_due(false), "three runs but only 120 s of play: not yet (both conditions)")
	G.ads.since_secs = 181.0
	ok(Ads.interstitial_due(false), "three runs and 181 s: due")
	var nexted2 := [false]
	Ads.show_interstitial_then(false, func(): nexted2[0] = true)   # nothing loaded: start right away
	ok(nexted2[0], "no interstitial ready: the next run starts immediately")
	# Ad-Free: nothing requested, nothing shown
	fresh_profile()
	G.ent.no_ads = true
	var fake2: Node = FakeAds.new()
	Ads.use_backend(fake2)
	Ads.start()
	Ads.load_ad("revive")
	Ads.load_ad("interstitial")
	G.ads = {"finished_total": 50, "since_runs": 10, "since_secs": 9999.0, "shown": 0}
	await wait(0.3)
	ok(fake2.started == 0 and fake2.loads == 0 and Ads.requests == 0 and not Ads.interstitial_due(false) and Ads.status("revive") == "off",
		"Ad-Free: the SDK is never started, no ad request, no interstitial")
	# Ad-Free bought during a session: loaded ads are dropped
	fresh_profile()
	var fake3: Node = FakeAds.new()
	Ads.use_backend(fake3)
	Ads.start()
	await wait(0.2)
	Ads.load_ad("revive")
	await wait(0.2)
	G.ent.no_ads = true
	Ads.disable()
	ok(not Ads.is_ready("revive") and not Ads.show_rewarded("revive", "x") and Ads.status("revive") == "off", "buying Ad-Free stops ads at once")
	# Ad-Free bought while an ad was still loading: the late answer is dropped, nothing more is requested
	fresh_profile()
	var fake4: Node = FakeAds.new()
	fake4.delay = 0.3
	Ads.use_backend(fake4)
	Ads.start()
	await wait(0.5)
	Ads.load_ad("revive")
	G.ent.no_ads = true
	Ads.disable()
	await wait(0.6)
	var r0: int = Ads.requests
	Ads.load_ad("revive")
	Ads.load_ad("interstitial")
	ok(not Ads.is_ready("revive") and Ads.requests == r0 and fake4.loads == 1 and not Ads.show_rewarded("revive", "y"),
		"Ad-Free during a load: the late ad is dropped, no new request", "loads %d" % fake4.loads)
	await consent_tests()

func consent_tests() -> void:
	## The three GDPR answers and the privacy options, driven only by what UMP reports (canRequestAds()).
	# 1. "Consent": ads may be requested
	fresh_profile()
	var f1: Node = FakeAds.new()
	Ads.use_backend(f1)
	Ads.start()
	await wait(0.2)
	Ads.load_ad("revive")
	await wait(0.2)
	ok(Ads.can_request and Ads.is_ready("revive") and f1.loads == 1, "consent: UMP allows requests, the rewarded ad loads")
	# 2. "Do not consent" where UMP answers canRequestAds()=false: nothing is requested at all
	fresh_profile()
	var f2: Node = FakeAds.new()
	f2.consent_can = false
	Ads.use_backend(f2)
	Ads.start()
	await wait(0.2)
	Ads.load_ad("revive")
	Ads.load_ad("double")
	Ads.load_ad("interstitial")
	await wait(0.2)
	ok(Ads.consent_done and not Ads.can_request and f2.loads == 0 and Ads.requests == 0 and Ads.status("revive") == "unavailable",
		"declined and UMP says no: no ad request, the video button is unavailable")
	# 2b. "Do not consent" where UMP still answers true (TCF: the ad SDK then serves limited / no ads itself)
	fresh_profile()
	var f2b: Node = FakeAds.new()
	f2b.fill = false   # the SDK may have nothing to serve without consent: a normal "no fill"
	Ads.use_backend(f2b)
	Ads.start()
	await wait(0.2)
	Ads.load_ad("revive")
	await wait(0.2)
	ok(f2b.loads == 1 and not Ads.is_ready("revive") and Ads.status("revive") == "unavailable" and not Ads.show_rewarded("revive", "z"),
		"declined but UMP allows requests: requested once, no fill is handled, nothing is shown")
	# 3. "Manage options" → privacy options: withdraw, then give consent again
	fresh_profile()
	var f3: Node = FakeAds.new()
	Ads.use_backend(f3)
	Ads.start()
	await wait(0.2)
	Ads.load_ad("revive")
	await wait(0.2)
	ok(Ads.privacy_required and Ads.is_ready("revive"), "privacy options entry required, an ad is loaded")
	f3.privacy_choice = false
	Ads.show_privacy_options()
	await wait(0.2)
	Ads.load_ad("double")
	await wait(0.2)
	ok(not Ads.can_request and not Ads.is_ready("revive") and not Ads.is_ready("double") and f3.loads == 1,
		"consent withdrawn in privacy options: loaded ad dropped, no new request")
	f3.privacy_choice = true
	Ads.show_privacy_options()
	await wait(0.2)
	Ads.load_ad("double")
	await wait(0.2)
	ok(Ads.can_request and Ads.is_ready("double") and f3.loads == 2, "consent given again: requests resume")
	# consent withdrawn while a request was in flight: the late ad is not kept
	fresh_profile()
	var f4: Node = FakeAds.new()
	f4.delay = 0.3
	Ads.use_backend(f4)
	Ads.start()
	await wait(0.5)
	Ads.load_ad("revive")
	f4.consent_can = false
	Ads.can_request = false
	await wait(0.6)
	ok(not Ads.is_ready("revive"), "an ad that arrives after consent was withdrawn is not kept")
	# canRequestAds() is asked again right before every request
	fresh_profile()
	var f5: Node = FakeAds.new()
	Ads.use_backend(f5)
	Ads.start()
	await wait(0.2)
	f5.consent_can = false
	Ads.load_ad("revive")
	ok(f5.loads == 0 and not Ads.can_request, "UMP answer changed after start: checked before the request, nothing requested")
	# offline: requestConsentInfoUpdate fails, the earlier session's answer decides
	for prev in [true, false]:
		fresh_profile()
		var f6: Node = FakeAds.new()
		f6.consent_error = "offline"
		f6.consent_can = prev
		f6.network_ok = false
		Ads.use_backend(f6)
		Ads.start()
		await wait(0.2)
		Ads.load_ad("revive")
		await wait(0.2)
		ok(Ads.consent_done and Ads.can_request == prev and f6.loads == (1 if prev else 0) and not Ads.is_ready("revive")
			and Ads.status("revive") == "unavailable", "offline consent error, earlier consent=%s: game goes on, no ad shown" % prev)
	# start arguments: test mode, no forced EEA without registered test devices
	fresh_profile()
	var f7: Node = FakeAds.new()
	Ads.use_backend(f7)
	Ads.start()
	await wait(0.1)
	ok(f7.last_start.size() == 4 and f7.last_start[0] == true and f7.last_start[1] == false,
		"closed test: test mode on, forced EEA off (no test devices registered)", str(f7.last_start))

# ---------------------------------------------------------------- rewards

func reward_tests() -> void:
	fresh_profile()
	G.meta.crystals = 100
	G.result = {"id": "att-1", "gems": 18, "doubled": false}
	ok(G.mark_reward_earned("double", "att-1", 18), "double crystals: reward recorded")
	ok(not G.mark_reward_earned("double", "att-1", 18), "recording it again is refused")
	restart_profile()      # killed between the reward and its payment
	ok(G.reward_state("double", "att-1") == "earned", "after a restart the earned-but-unpaid reward is still there")
	var paid := G.apply_double("att-1")
	var paid2 := G.apply_double("att-1")
	ok(paid == 18 and paid2 == 0 and G.meta.crystals == 118 and G.result.doubled, "it pays 18 more exactly once (100 → 118)", "paid %d then %d" % [paid, paid2])
	restart_profile()
	ok(G.apply_double("att-1") == 0 and G.meta.crystals == 118, "after another restart it is not paid again")
	ok(G.apply_double("att-2") == 0, "an attempt without a recorded reward pays nothing")

func admob_config_tests() -> void:
	## The real AdMob IDs are stored, but the closed-test build keeps Google's test IDs everywhere.
	var cfg := ConfigFile.new()
	cfg.load("res://config/monetization.cfg")
	var app_re := RegEx.create_from_string("^ca-app-pub-(\\d{16})~\\d{10}$")
	var unit_re := RegEx.create_from_string("^ca-app-pub-(\\d{16})/\\d{10}$")
	var app := String(cfg.get_value("admob", "real_app_id", ""))
	var m := app_re.search(app)
	ok(m != null, "real AdMob App ID has the App ID format (~)", app)
	var pub := m.get_string(1) if m else "?"
	var units := {}
	for k in ["rewarded_revive", "rewarded_double", "interstitial"]:
		var u := String(cfg.get_value("admob", "real_" + k, ""))
		var um := unit_re.search(u)
		ok(um != null and um.get_string(1) == pub, "real %s is an ad unit ID (/) of the same publisher" % k, u)
		units[u] = k
	ok(units.size() == 3, "three different real ad units (one per placement)")
	ok(bool(cfg.get_value("admob", "use_test_ads", false)), "closed-test build: use_test_ads=true")
	ok(Ads.test_ads() and Ads.unit("revive").begins_with("ca-app-pub-3940256099942544/")
		and Ads.unit("double").begins_with("ca-app-pub-3940256099942544/")
		and Ads.unit("interstitial").begins_with("ca-app-pub-3940256099942544/"), "test mode: every placement requests Google's test units")
	# production switch (simulated in memory only): each placement gets its own real unit
	var saved = Ads.cfg.get_value("admob", "use_test_ads")
	Ads.cfg.set_value("admob", "use_test_ads", false)
	ok(not Ads.test_ads() and Ads.unit("revive") == String(cfg.get_value("admob", "real_rewarded_revive"))
		and Ads.unit("double") == String(cfg.get_value("admob", "real_rewarded_double"))
		and Ads.unit("interstitial") == String(cfg.get_value("admob", "real_interstitial")),
		"production mode: revive → revive unit, double → double unit, interstitial → interstitial unit")
	Ads.cfg.set_value("admob", "use_test_ads", saved)
	ok(Ads.test_ads(), "test mode restored")
	admob_ids_tests(cfg)

func admob_ids_tests(cfg: ConfigFile) -> void:
	## AndroidManifest App ID and the forced-EEA rule (scripts/admob_ids.gd, used by the export plugin).
	var ids := preload("res://scripts/admob_ids.gd")
	var real := String(cfg.get_value("admob", "real_app_id"))
	ok(ids.manifest_app_id(cfg) == "ca-app-pub-6607622048074974~8739194745", "manifest App ID = the real Deep Bounce App ID", ids.manifest_app_id(cfg))
	var c := ConfigFile.new()
	c.parse(FileAccess.get_file_as_string("res://config/monetization.cfg"))
	c.set_value("admob", "use_test_ads", true)
	ok(ids.manifest_app_id(c) == real and ids.unit(c, "revive") == "ca-app-pub-3940256099942544/5224354917"
		and ids.unit(c, "double") == "ca-app-pub-3940256099942544/5224354917"
		and ids.unit(c, "interstitial") == "ca-app-pub-3940256099942544/1033173712",
		"test mode: real App ID in the manifest, Google's test rewarded/interstitial units for every request")
	c.set_value("admob", "use_test_ads", false)
	ok(ids.manifest_app_id(c) == real and ids.unit(c, "revive") == String(cfg.get_value("admob", "real_rewarded_revive")),
		"production mode: the same real App ID, real units")
	c.set_value("admob", "real_app_id", "")
	ok(ids.manifest_app_id(c) == String(cfg.get_value("admob", "test_app_id")) and ids.test_mode(c)
		and ids.unit(c, "revive").begins_with("ca-app-pub-3940256099942544/"), "no real App ID: test App ID and test units")
	var e := ConfigFile.new()
	e.parse(FileAccess.get_file_as_string("res://config/monetization.cfg"))
	e.set_value("admob", "use_test_ads", true)
	e.set_value("admob", "debug_geography_eea", true)
	e.set_value("admob", "test_device_ids", "")
	ok(not ids.debug_eea(e), "forced EEA requested but no test device registered: off for every tester")
	e.set_value("admob", "test_device_ids", " ABCDEF0123456789, ,33BE2250B43518CCDA7DE426D04EE231 ")
	ok(ids.debug_eea(e) and ids.test_devices(e) == "ABCDEF0123456789,33BE2250B43518CCDA7DE426D04EE231",
		"forced EEA only together with the registered hashed test devices", ids.test_devices(e))
	e.set_value("admob", "use_test_ads", false)
	ok(not ids.debug_eea(e), "production mode: never a forced EEA")
	ok(not bool(cfg.get_value("admob", "debug_geography_eea", true)) and String(cfg.get_value("admob", "test_device_ids", "x")) == "",
		"shipped config: forced EEA off, no test devices")
	var plugin := FileAccess.get_file_as_string("res://addons/DeepBounceAds/export_plugin.gd")
	ok(plugin.contains("ADMOB.manifest_app_id(cfg)") and not plugin.contains('get_value("admob", "test_app_id"'),
		"export plugin writes the App ID from admob_ids.gd (real ID, also in test mode)")

func signature_tests() -> void:
	## Known-answer vectors made outside Godot (OpenSSL SHA1withRSA, cross-checked with Java's
	## Signature.getInstance("SHA1withRSA") — the scheme of Google's Security.java samples).
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/billing_vectors.json"))
	var key: String = v.public_key_b64
	for name in ["purchased", "pending", "utf8"]:
		ok(Store.verify_signature(v[name].original_json, v[name].signature_sha1, key), "Google-format SHA1withRSA vector '%s' verifies" % name)
	ok(Store.verify_signature(v.purchased.original_json, v.purchased.signature_sha256, key), "SHA256withRSA with the same key is also accepted")
	var js: String = v.purchased.original_json
	var sig: String = v.purchased.signature_sha1
	ok(not Store.verify_signature(js.replace("db_no_ads", "db_ball_amber"), sig, key), "edited product id fails")
	ok(not Store.verify_signature(js.replace('"purchaseState":0', '"purchaseState":4'), sig, key), "edited purchase state fails")
	ok(not Store.verify_signature(js + " ", sig, key), "one extra byte fails")
	ok(not Store.verify_signature(js, v.pending.signature_sha1, key), "another purchase's signature fails")
	var other := Crypto.new().generate_rsa(2048).save_to_string(true).replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace("\n", "")
	ok(not Store.verify_signature(js, sig, other), "a different licence key fails")
	ok(not Store.verify_signature(js, "", key) and not Store.verify_signature(js, "not base64 !!", key)
		and not Store.verify_signature("", sig, key) and not Store.verify_signature(js, sig, "garbage"), "empty or malformed signature / key / JSON fail")
	var spaced := ""
	for i in range(0, key.length(), 64):
		spaced += key.substr(i, 64) + "\n"
	ok(Store.verify_signature(js, sig, spaced), "a licence key pasted with line breaks still works")
	# the signed JSON must describe this purchase
	var good := {"purchase_token": "kdmjeahpgfnbblkcfhkpojnm.AO-J1Oy2aQ3Wq9X0test", "product_ids": ["db_no_ads"], "purchase_state": 1,
		"original_json": js, "signature": sig, "package_name": "com.deepbounce.game"}
	ok(Store.check_purchase(good, key) == "", "matching purchase passes")
	var t1 := good.duplicate(true); t1.purchase_token = "someone-elses-token"
	ok(Store.check_purchase(t1, key) == "token", "genuine JSON reused for another token is rejected", Store.check_purchase(t1, key))
	var t2 := good.duplicate(true); t2.product_ids = ["db_cannon_obsidian"]
	ok(Store.check_purchase(t2, key) == "product", "genuine JSON reused for another product is rejected")
	var pend := {"purchase_token": "pendingtokenexample.AO-J1Oz9pending", "product_ids": ["db_support_large"], "purchase_state": 1,
		"original_json": v.pending.original_json, "signature": v.pending.signature_sha1}
	ok(Store.check_purchase(pend, key) == "state", "a pending payment presented as completed is rejected")
	pend.purchase_state = 2
	ok(Store.check_purchase(pend, key) == "", "the same pending purchase reported as pending passes")
	ok(Store.check_purchase(t1, "") == "", "no licence key: nothing can be checked (Closed Alpha only)")
	# end to end with a key: the simulated Google Play signs like the real one
	var priv := Crypto.new().generate_rsa(2048)
	var pub := priv.save_to_string(true).replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace("\n", "")
	fresh_profile()
	var f: Node = new_store()
	f.sign_key = priv
	Store.license_key = pub
	Store.start()
	await wait(0.3)
	var gems_before := int(G.support.count)
	for pid in CATALOG.product_ids():
		f.next[pid] = "approve"
		results.clear()
		Store.buy(pid)
		await wait(0.4)
		ok(last_status(pid) == "granted", "signed purchase of %s is granted" % pid, last_status(pid))
	var perm := 0
	for pid in CATALOG.product_ids():
		if CATALOG.product(pid).type == "permanent":
			perm += 1
			ok(G.ent.products.has(pid), "%s owned" % pid)
	ok(int(G.support.count) - gems_before == 4, "the four support contributions are counted once each", str(int(G.support.count) - gems_before))
	await wait(0.4)
	var acked := 0
	var consumed := 0
	for tok in G.purchases:
		var e: Dictionary = G.purchases[tok]
		if CATALOG.product(e.pid).type == "permanent":
			acked += 1 if e.acked else 0
		else:
			consumed += 1 if e.consumed else 0
	ok(acked == perm and consumed == 4, "permanent items acknowledged, support items consumed", "%d/%d acked, %d/4 consumed" % [acked, perm, consumed])
	# replay: Google Play reports the same purchases again (restart / restore) — nothing is granted twice
	var count_before := int(G.support.count)
	Store.restore()
	await wait(0.4)
	ok(int(G.support.count) == count_before and G.ent.products.size() == perm, "restore with signed purchases grants nothing twice")
	# a forged copy: real signature, but the dictionary claims another product
	results.clear()
	fresh_profile()
	var forged: Dictionary = f.account.values()[0].duplicate(true)
	forged.product_ids = ["db_cannon_obsidian"]
	Store._on_purchase_updated({"response_code": 0, "purchases": [forged]})
	ok(not G.ent.products.has("db_cannon_obsidian") and last_status("db_cannon_obsidian") == "unverified", "forged purchase (signature of another item) grants nothing, the player is told it could not be verified")
	var unsigned: Dictionary = f.account.values()[0].duplicate(true)
	unsigned.signature = ""
	Store._on_purchase_updated({"response_code": 0, "purchases": [unsigned]})
	ok(G.ent.products.is_empty(), "purchase without a signature grants nothing when a licence key is set")
	# licence key handling
	ok(Store.key_state("") == "missing" and Store.key_state("not a key") == "invalid" and Store.key_state("QUJDRA==") == "invalid"
		and Store.key_state(pub) == "ok", "licence key: missing / invalid / valid are told apart")
	var pem_wrapped := "-----BEGIN PUBLIC KEY-----\n" + pub + "\n-----END PUBLIC KEY-----"
	ok(Store.key_state(pem_wrapped) == "ok" and Store.key_state("  " + pub.substr(0, 40) + "\n" + pub.substr(40) + "\n") == "ok",
		"a key pasted with PEM lines, spaces or line breaks still loads")
	fresh_profile()
	f = new_store()
	f.sign_key = priv
	Store.license_key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAinvalid"
	Store.start()
	await wait(0.3)
	results.clear()
	Store.buy("db_ball_amber")
	await wait(0.4)
	ok(not G.owns("ball", "amber") and last_status("db_ball_amber") == "unverified", "a broken licence key fails closed: nothing granted")
	# signed JSON that does not match what the plugin reports
	var base := {"orderId": "GPA.1", "packageName": "com.deepbounce.game", "productId": "db_ball_amber", "purchaseTime": 1,
		"purchaseState": 0, "purchaseToken": "tok-x", "quantity": 1, "acknowledged": false}
	var cases := [["packageName", null, "package"], ["purchaseState", 1, "state"], ["purchaseToken", "tok-y", "token"], ["productId", "db_no_ads", "product"]]
	for c in cases:
		var j: Dictionary = base.duplicate()
		if c[1] == null:
			j.erase(c[0])
		else:
			j[c[0]] = c[1]
		var sj := JSON.stringify(j)
		var ssig := Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA1, sj.sha1_buffer(), priv))
		var spu := {"purchase_token": "tok-x", "package_name": "com.deepbounce.game", "purchase_state": 1, "product_ids": ["db_ball_amber"],
			"original_json": sj, "signature": ssig}
		ok(Store.check_purchase(spu, pub) == c[2], "signed JSON with %s=%s is rejected (%s)" % [c[0], str(c[1]), c[2]], Store.check_purchase(spu, pub))
	var good_js := JSON.stringify(base)
	var good_pu := {"purchase_token": "tok-x", "package_name": "com.deepbounce.game", "purchase_state": 1, "product_ids": ["db_ball_amber"],
		"original_json": good_js, "signature": Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA1, good_js.sha1_buffer(), priv))}
	ok(Store.check_purchase(good_pu, pub) == "", "the same JSON unchanged passes")
	# pending with a key: waits, then is granted once the payment completes
	fresh_profile()
	f = new_store()
	f.sign_key = priv
	Store.license_key = pub
	Store.start()
	await wait(0.3)
	f.next["db_ball_frost"] = "pending"
	Store.buy("db_ball_frost")
	await wait(0.4)
	ok(last_status("db_ball_frost") == "pending" and not G.owns("ball", "frost"), "signed pending purchase: nothing granted yet")
	f.approve_pending()
	Store._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await wait(0.4)
	ok(G.owns("ball", "frost"), "after the payment completes (re-signed by Google Play) the item is granted")
	f.refund("db_ball_frost")
	await refund_confirmed()
	ok(not G.owns("ball", "frost"), "refund confirmed by Google Play removes the item")
	Store.license_key = ""
