// CHOMPStation Edits over this entire file.
//
// Control computer for point defense batteries.
// Handles control UI, but also coordinates their fire to avoid overkill.
//

GLOBAL_LIST_BOILERPLATE(pointdefense_controllers, /obj/machinery/pointdefense_control)
GLOBAL_LIST_BOILERPLATE(pointdefense_turrets, /obj/machinery/pointdefense)

/obj/machinery/pointdefense_control
	name = "fire assist mainframe"
	desc = "A specialized computer designed to synchronize a variety of weapon systems and a vessel's astronav data."
	icon = 'icons/obj/pointdefense.dmi'
	icon_state = "control"
	power_channel = EQUIP // CHOMPStation Edit Starts
	use_power = USE_POWER_ACTIVE 
	active_power_usage = 5 KILOWATTS // CHOMPStation Edit Ends
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/weapon/circuitboard/pointdefense_control
	var/list/targets = list()  // Targets being engaged by associated batteries
	var/id_tag = null

/obj/machinery/pointdefense_control/Initialize(mapload)
	. = ..()
	if(id_tag)
		//No more than 1 controller please.
		for(var/obj/machinery/pointdefense_control/PC as anything in GLOB.pointdefense_controllers)
			if(PC != src && PC.id_tag == id_tag)
				warning("Two [src] with the same id_tag of [id_tag]")
				id_tag = null
	// TODO - Remove this bit once machines are converted to Initialize
	if(ispath(circuit))
		circuit = new circuit(src)
	default_apply_parts()

/obj/machinery/pointdefense_control/get_description_interaction()
	. = ..()
	if(!id_tag)
		. += "[desc_panel_image("multitool")]to set ident tag"

/obj/machinery/pointdefense_control/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PointDefenseControl") // 400, 600
		ui.open()

/obj/machinery/pointdefense_control/attack_hand(mob/user)
	if(..())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/pointdefense_control/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	if(action == "toggle_active")
		var/obj/machinery/pointdefense/PD = locate(params["target"])
		if(!istype(PD))
			return FALSE

		//if(!lan || !lan.is_connected(PD))
		if(PD.id_tag != id_tag)
			return FALSE

		if(!(get_z(PD) in GetConnectedZlevels(get_z(src))))
			to_chat(usr, "<span class='warning'>[PD] is not within control range.</span>")
			return FALSE

		if(!PD.Activate()) //Activate() whilst the device is active will return false.
			PD.Deactivate()
		return TRUE

/obj/machinery/pointdefense_control/tgui_data(mob/user)
	var/list/data = list()
	data["id"] = id_tag
	var/list/turrets = list()
	if(id_tag)
		var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
		for(var/i = 1 to LAZYLEN(GLOB.pointdefense_turrets))
			var/obj/machinery/pointdefense/PD = GLOB.pointdefense_turrets[i]
			if(!(PD.id_tag == id_tag && (get_z(PD) in connected_z_levels)))
				continue
			var/list/turret = list()
			turret["id"] =          "#[i]"
			turret["ref"] =         "\ref[PD]"
			turret["active"] =       PD.active
			turret["effective_range"] = PD.active ? "[PD.kill_range] meter\s" : "OFFLINE."
			turret["reaction_wheel_delay"] = PD.active ? "[(PD.rotation_speed / (1 SECONDS))] second\s" : "OFFLINE."
			turret["recharge_time"] = PD.active ? "[(PD.charge_cooldown / (1 SECONDS))] second\s" : "OFFLINE."

			turrets += list(turret)

	data["turrets"] = turrets
	return data

/obj/machinery/pointdefense_control/attackby(var/obj/item/W, var/mob/user)
	if(W?.is_multitool())
		var/new_ident = tgui_input_text(user, "Enter a new ident tag.", "[src]", id_tag)
		if(new_ident && new_ident != id_tag && user.Adjacent(src) && CanInteract(user, GLOB.tgui_physical_state))
			// Check for duplicate controllers with this ID
			for(var/obj/machinery/pointdefense_control/PC as anything in GLOB.pointdefense_controllers)
				if(PC != src && PC.id_tag == id_tag)
					to_chat(user, "<span class='warning'>The [new_ident] network already has a controller.</span>")
					return
			to_chat(user, "<span class='notice'>You register [src] with the [new_ident] network.</span>")
			id_tag = new_ident
		return
	if(default_deconstruction_screwdriver(user, W))
		return
	if(default_deconstruction_crowbar(user, W))
		return
	if(default_part_replacement(user, W))
		return
	return ..()

//
// The acutal point defense battery
//

// CHOMPStation Edits Begin: PD Turrets won't use power now, only the PD Control Mainframe. These edits go to the end of the file.
/obj/machinery/pointdefense
	name = "\improper point defense battery"
	icon = 'icons/obj/pointdefense.dmi'
	icon_state = "pointdefense2"
	desc = "A Kuiper pattern anti-meteor battery. Capable of destroying most threats in a single salvo."
	description_info = "Must have the same ident tag as a fire assist mainframe on the same facility."
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/weapon/circuitboard/pointdefense
	//idle_power_usage = 0.1 KILOWATTS // CHOMPStation Edit
	//active_power_usage = 1 KILOWATTS // CHOMPStation Edit
	appearance_flags = PIXEL_SCALE
	var/active = TRUE
	var/charge_cooldown = 1 SECOND  //time between it can fire at different targets
	var/last_shot = 0
	var/kill_range = 18
	var/rotation_speed = 4.5 SECONDS  //How quickly we turn to face threats
	var/engaging = FALSE
	var/id_tag = null

/obj/machinery/pointdefense/Initialize()
	. = ..()
	// TODO - Remove this bit once machines are converted to Initialize
	if(ispath(circuit))
		circuit = new circuit(src)
	default_apply_parts()
	// if(anchored)
	// 	connect_to_network()
	update_icon()
	var/image/I = image(icon, icon_state = "[icon_state]_under")
	I.appearance_flags |= RESET_TRANSFORM
	underlays += I

// /obj/machinery/pointdefense/examine(mob/user)
// 	. = ..()
// 	if(powernet)
// 		. += "It is connected to a power cable below."

/obj/machinery/pointdefense/get_description_interaction()
	. = ..()
	if(!id_tag)
		. += "[desc_panel_image("multitool")]to set ident tag and connect to a mainframe."

/obj/machinery/pointdefense/update_icon()
	if(!active || !id_tag || inoperable())
		icon_state = "[initial(icon_state)]_off"
	else
		icon_state = initial(icon_state)

/obj/machinery/pointdefense/default_unfasten_wrench(var/mob/user, var/obj/item/weapon/W, var/time)
	if((. = ..()))
		src.transform = null // Reset rotation if we're anchored/unanchored

////////// This machine is willing to take power from cables OR APCs.  Handle NOPOWER stat specially here! ////////
/*
/obj/machinery/pointdefense/connect_to_network()
	if((. = ..()))
		stat &= ~NOPOWER // We now ignore APC power
		update_icon()

/obj/machinery/pointdefense/disconnect_from_network()
	if((. = ..()))
		power_change() // We're back on APC power.

/obj/machinery/pointdefense/power_change()
	if(powernet)
		return // We don't care, we are cable powered anyway
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()

// Decide where to get the power to fire from
/obj/machinery/pointdefense/use_power_oneoff(var/amount, var/chan = -1)
	if(powernet)
		return draw_power(amount)
	else if(powered(chan))
		use_power(amount, chan)
		return amount
	return 0	*/

// Find controller with the same tag on connected z levels (if any)
/obj/machinery/pointdefense/proc/get_controller()
	if(!id_tag)
		return null
	var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
	for(var/obj/machinery/pointdefense_control/PDC as anything in GLOB.pointdefense_controllers)
		if(PDC.id_tag == id_tag && (get_z(PDC) in connected_z_levels))
			return PDC

/obj/machinery/pointdefense/attackby(var/obj/item/W, var/mob/user)
	if(W?.is_multitool())
		var/new_ident = tgui_input_text(user, "Enter a new ident tag.", "[src]", id_tag)
		if(new_ident && new_ident != id_tag && user.Adjacent(src) && CanInteract(user, GLOB.tgui_physical_state))
			to_chat(user, "<span class='notice'>You register [src] with the [new_ident] network.</span>")
			id_tag = new_ident
		return
	if(default_deconstruction_screwdriver(user, W))
		return
	if(default_deconstruction_crowbar(user, W))
		return
	if(default_part_replacement(user, W))
		return
	if(default_unfasten_wrench(user, W, 40))
		return
	return ..()

//Guns cannot shoot through hull or generally dense turfs.
/obj/machinery/pointdefense/proc/space_los(meteor)
	for(var/turf/T in getline(src,meteor))
		if(T.density)
			return FALSE
	return TRUE

/obj/machinery/pointdefense/proc/Shoot(var/weakref/target)
	var/obj/effect/meteor/M = target.resolve()
	if(!istype(M))
		return
	engaging = TRUE
	var/Angle = round(Get_Angle(src,M))
	var/matrix/rot_matrix = matrix()
	rot_matrix.Turn(Angle)
	addtimer(CALLBACK(src, .proc/finish_shot, target), rotation_speed)
	animate(src, transform = rot_matrix, rotation_speed, easing = SINE_EASING)

	set_dir(ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH)

/obj/machinery/pointdefense/proc/finish_shot(var/weakref/target)
	//Cleanup from list
	var/obj/machinery/pointdefense_control/PC = get_controller()
	if(istype(PC))
		PC.targets -= target

	engaging = FALSE
	last_shot = world.time
	var/obj/effect/meteor/M = target.resolve()
	if(!istype(M))
		return
	/*if(use_power_oneoff(active_power_usage) < active_power_usage)
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(5, 1, src)
		s.start()
		visible_message("[src] sputters as browns out while attempting to fire.")
		flick(src, "[initial(icon_state)]_off")
		return	*/
	//We throw a laser but it doesnt have to hit for meteor to explode
	var/obj/item/projectile/beam/pointdefense/beam = new(get_turf(src))
	playsound(src, 'sound/weapons/mandalorian.ogg', 75, 1)
	beam.launch_projectile(target = M.loc, user = src)
	M.make_debris()
	qdel(M)

/obj/machinery/pointdefense/process()
	..()
	if(!anchored || stat & (BROKEN))
		return
	if(!active)
		return
	/*
	var/desiredir = ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH
	if(dir != desiredir)
		set_dir(desiredir)
	*/
	if(LAZYLEN(GLOB.meteor_list) > 0)
		find_and_shoot()

/obj/machinery/pointdefense/proc/find_and_shoot()
	if(LAZYLEN(GLOB.meteor_list) == 0)
		return
	if(engaging || ((world.time - last_shot) < charge_cooldown))
		return

	var/obj/machinery/pointdefense_control/PC = get_controller()
	if(!istype(PC) || !PC.powered(EQUIP))
		return

	var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
	for(var/obj/effect/meteor/M in GLOB.meteor_list)
		var/already_targeted = FALSE
		for(var/weakref/WR in PC.targets)
			var/obj/effect/meteor/m = WR.resolve()
			if(m == M)
				already_targeted = TRUE
				break
			if(!istype(m))
				PC.targets -= WR

		if(already_targeted)
			continue

		if(!(M.z in connected_z_levels))
			continue
		if(get_dist(M, src) > kill_range)
			continue
		if(!emagged && space_los(M))
			var/weakref/target = weakref(M)
			PC.targets += target
			Shoot(target)
			return

/obj/machinery/pointdefense/RefreshParts()
	. = ..()
	// Calculates an average rating of components that affect shooting rate
	var/shootrate_divisor = total_component_rating_of_type(/obj/item/weapon/stock_parts/capacitor)

	charge_cooldown = 2 SECONDS / (shootrate_divisor ? shootrate_divisor : 1)

	//Calculate max shooting range
	var/killrange_multiplier = total_component_rating_of_type(/obj/item/weapon/stock_parts/capacitor)
	killrange_multiplier += 1.5 * total_component_rating_of_type(/obj/item/weapon/stock_parts/scanning_module)

	kill_range = 10 + 4 * killrange_multiplier

	var/rotation_divisor = total_component_rating_of_type(/obj/item/weapon/stock_parts/manipulator)
	rotation_speed = 4.5 SECONDS / (rotation_divisor ? rotation_divisor : 1)

/obj/machinery/pointdefense/proc/Activate()
	if(active)
		return FALSE

	playsound(src, 'sound/weapons/flash.ogg', 100, 0)
	//update_use_power(USE_POWER_IDLE)
	active = TRUE
	update_icon()
	return TRUE

/obj/machinery/pointdefense/proc/Deactivate()
	if(!active)
		return FALSE
	playsound(src, 'sound/machines/apc_nopower.ogg', 50, 0)
	//update_use_power(USE_POWER_OFF)
	active = FALSE
	update_icon()
	return TRUE

//
// Projectile Beam Definitions
//

/obj/item/projectile/beam/pointdefense
	name = "point defense salvo"
	icon_state = "laser"
	damage = 15
	damage_type = ELECTROCUTE //You should be safe inside a voidsuit
	sharp = FALSE //"Wide" spectrum beam
	light_color = COLOR_GOLD

	muzzle_type = /obj/effect/projectile/muzzle/pointdefense
	tracer_type = /obj/effect/projectile/tracer/pointdefense
	impact_type = /obj/effect/projectile/impact/pointdefense


/obj/effect/projectile/tracer/pointdefense
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "beam_pointdef"

/obj/effect/projectile/muzzle/pointdefense
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "muzzle_pointdef"

/obj/effect/projectile/impact/pointdefense
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "impact_pointdef"
