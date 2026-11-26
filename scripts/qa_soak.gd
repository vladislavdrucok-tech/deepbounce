extends RefCounted
## Long play session for memory and object leaks (run with --qa=soak under a renderer):
## many runs and volleys through the real game loop with frames drawn, sampling static memory, objects, nodes
## and resources. A leak shows as steady growth after the warm-up; a healthy game levels off.

var VOLLEYS := 150        # --soak=N for a longer session
const SAMPLE_EVERY := 15

func run(qa) -> void:
	var main = qa.main
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak="):
			VOLLEYS = int(a.substr(7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	G.meta.tutorial = 6
	main.start_new_run(5150)
	var volleys := 0
	var runs := 1
	var samples: Array = []
	var t0 := Time.get_ticks_msec()
	while volleys < VOLLEYS:
		var s = main.sim
		if s.phase == Sim.PH_UPGRADE:
			main.pick_upgrade(s.upgrade_opts[rng.randi_range(0, s.upgrade_opts.size() - 1)])
		elif s.phase == Sim.PH_AIM:
			main.hud.hide_hint()
			main._fire(rng.randf_range(0.35, PI - 0.35))
			volleys += 1
			var guard := 0
			while main.sim.phase == Sim.PH_VOLLEY and guard < 20000:
				main._process(1.0 / 60.0)
				guard += 1
				if guard % 6 == 0:
					await qa.frames(1)   # draw: effects, trails and particles are created and freed as in play
			await qa.frames(2)
			if volleys % SAMPLE_EVERY == 0:
				await qa.frames(30)      # let effects finish
				samples.append({"v": volleys, "mem": OS.get_static_memory_usage() / 1048576.0,
					"obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
					"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
					"res": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
					"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
					"vram": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0})
				var x: Dictionary = samples[-1]
				qa.log_line("soak %3d volleys, %d runs: static %.1f MB, objects %d, nodes %d, resources %d, orphans %d, video %.1f MB"
					% [x.v, runs, x.mem, x.obj, x.nodes, x.res, x.orphans, x.vram])
		else:
			main.over_timer = -1.0
			main.won_timer = -1.0
			main._finish()
			await qa.frames(3)
			main.start_new_run(5150 + runs)
			runs += 1
	qa.log_line("soak: %d volleys, %d runs in %.0f s" % [volleys, runs, (Time.get_ticks_msec() - t0) / 1000.0])
	# A leak keeps growing; caches (glyphs of new number sizes, textures of new stone sizes) grow in steps while new
	# content appears and then stop. Judged on the last third of the session.
	var a: Dictionary = samples[1]
	var m: Dictionary = samples[int(samples.size() * 2 / 3)]
	var b: Dictionary = samples[-1]
	qa.log_line("soak growth: after warm-up %+.1f MB (%+.1f%%), in the last third %+.1f MB (%+.1f%%); objects %+d, nodes %+d, orphans %d"
		% [b.mem - a.mem, 100.0 * (b.mem - a.mem) / a.mem, b.mem - m.mem, 100.0 * (b.mem - m.mem) / m.mem, b.obj - a.obj,
		b.nodes - a.nodes, b.orphans])
	qa.check(b.mem - m.mem < m.mem * 0.03 and absi(b.nodes - a.nodes) < 200 and b.orphans < 50,
		"no leak over %d volleys / %d runs (memory levels off, nodes stable, no orphans)" % [volleys, runs],
		"last third %+.1f MB, nodes %+d, orphans %d" % [b.mem - m.mem, b.nodes - a.nodes, b.orphans])
	G.reset_defaults()
	G.save_game()
