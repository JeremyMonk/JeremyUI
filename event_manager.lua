function(event, ...)
    
    local aura_env = aura_env
    
    -- Prevent code execution during loading screens or WA options window
    if event == "LOADING_SCREEN_DISABLED" then
        aura_env.world_loaded = true
    elseif event == "LOADING_SCREEN_ENABLED" then
        aura_env.world_loaded = false
        return false
    elseif event == "OPTIONS" or not aura_env.world_loaded then
        return false
    end
    
    local _GetTime = GetTime
    local GetTime = function()
        return aura_env.frameTime or _GetTime()
    end
    
    if event == "FRAME_UPDATE" then
        aura_env.frameTime = _GetTime()
    end
    
    -- This should never occur
    if not aura_env.CPlayer then
        return false
    end
    
    -- Cache Globals
    local Player = aura_env.CPlayer
    local Combat = Player.combat
    local spec = Player.spec
    
    local bit = bit
    local bit_band = bit.band
    local C_NamePlate = C_NamePlate
    local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
    local GetNamePlates = C_NamePlate.GetNamePlates
    local C_PaperDollInfo = C_PaperDollInfo
    local GetStaggerPercentage = C_PaperDollInfo.GetStaggerPercentage
    local C_Scenario = C_Scenario
    local GetCriteriaInfo = C_Scenario.GetCriteriaInfo
    local GetInfo = C_Scenario.GetInfo
    local GetStepInfo = C_Scenario.GetStepInfo
    local C_UnitAuras = C_UnitAuras
    local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
    local GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot
    local CheckInteractDistance = CheckInteractDistance
    local COMBATLOG_OBJECT_AFFILIATION_MASK = COMBATLOG_OBJECT_AFFILIATION_MASK
    local COMBATLOG_OBJECT_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE
    local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
    local debugprofilestart = debugprofilestart
    local debugprofilestop = debugprofilestop
    local floor = floor
    local frameTime = GetTime()
    local GetPowerRegen = GetPowerRegen
    local GetRaidTargetIndex = GetRaidTargetIndex
    local GetSpellCharges = GetSpellCharges
    local GetSpellCooldown = GetSpellCooldown
    local GetUnitSpeed = GetUnitSpeed
    local global_modifier = aura_env.global_modifier
    local InCombatLockdown = InCombatLockdown
    local ipairs = ipairs
    local IsMounted = IsMounted
    local IsSpellKnown = IsSpellKnown
    local LE_SCENARIO_TYPE_CHALLENGE_MODE = LE_SCENARIO_TYPE_CHALLENGE_MODE
    local LibStub = LibStub
    local math = math
    local max = math.max
    local min = math.min
    local pairs = pairs
    local print = print
    local select = select
    local SetRaidTarget = SetRaidTarget
    local string = string
    local find = string.find
    local gsub = string.gsub
    local len = string.len
    local lower = string.lower
    local sub = string.sub
    local table = table
    local targetAuraEffect = aura_env.targetAuraEffect
    local tonumber = tonumber
    local tostring = tostring
    local type = type
    local UnitAffectingCombat = UnitAffectingCombat
    local UnitAttackSpeed = UnitAttackSpeed
    local UnitAuraSlots = UnitAuraSlots
    local UnitChannelInfo = UnitChannelInfo
    local UnitExists = UnitExists
    local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
    local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
    local UnitGroupRolesAssigned = UnitGroupRolesAssigned
    local UnitGUID = UnitGUID
    local UnitHealth = UnitHealth
    local UnitHealthMax = UnitHealthMax
    local UnitIsDead = UnitIsDead
    local UnitIsGroupLeader = UnitIsGroupLeader
    local UnitIsPlayer = UnitIsPlayer
    local UnitLevel = UnitLevel
    local UnitName = UnitName
    local UnitPower = UnitPower
    local UnitPowerMax = UnitPowerMax
    local UnitStagger = UnitStagger
    local UnitStat = UnitStat
    local UnitThreatSituation = UnitThreatSituation
    local WA_IterateGroupMembers = WA_IterateGroupMembers
    local WeakAuras = WeakAuras
    local gcdDuration = WeakAuras.gcdDuration
    local ScanEvents = WeakAuras.ScanEvents 
    
    local insert = function ( t, v )
        t[ #t + 1 ] = v
    end
    local next = next
    local t_sort = table.sort
    local sort = function( t, func )
        if not func then
            t_sort( t )
        else
            t_sort( t, function( l, r )
                    if not l then 
                        return false
                    elseif not r then
                        return true
                    else
                        return func( l, r )
                    end
            end )
        end
    end     
    
    local profiler_enabled = false
    aura_env.profiler_out = ( profiler_enabled and aura_env.profiler_out ) or {}
    local profilerStart = function() if profiler_enabled then debugprofilestart() end end
    local profilerEnd = function( desc )
        if profiler_enabled then
            local profiler_t = debugprofilestop()
            if profiler_t and profiler_t > 0 then
                aura_env.profiler_out[ desc ] = profiler_t
            end
        end
    end
    
    -- Main worker thread
    if event == "FRAME_UPDATE" then
        
        local fullUpdate = false
        
        -- Development Debugging Option
        if profiler_enabled and next( aura_env.profiler_out ) ~= nil then
            ScanEvents( "JEREMYUI_PROFILER", aura_env.profiler_out )
        end
        
        -- Modulate update speed based on framerate
        if aura_env.frame_pace then
            local delta = frameTime - aura_env.frame_pace
            local modulate = max( 0.0167, delta ) / 0.0167
            aura_env.update_rate = min( 1, modulate * 0.5 )
        end
        aura_env.frame_pace = frameTime
        
        if not aura_env.RECENT_UPDATE or aura_env.RECENT_UPDATE < frameTime - 0.5 then
            profilerStart()
            
            aura_env.RECENT_UPDATE = frameTime
            
            local recentDamage = aura_env.danger_a + aura_env.danger_b
            
            for index, damage in pairs( Combat.recent_damage ) do
                local expire = damage.expire
                if not expire or expire <= frameTime then
                    Combat.recent_damage[ index ] = nil
                else
                    recentDamage = recentDamage + ( damage.amount or 0 )
                end
            end
            
            -- Used for Touch of Karma evaluation 
            Player.recent_dtps = recentDamage / aura_env.RECENT_DURATION
            
            profilerEnd( "Parse Recent Damage" )
        end
        
        if not aura_env.last 
        or aura_env.fast 
        or aura_env.tick_update and aura_env.tick_update < frameTime
        or aura_env.last < frameTime - aura_env.update_rate then
            
            -- Movement Rate / Speed
            if aura_env.last then
                
                local cur_speed = GetUnitSpeed( "player" )
                
                if InCombatLockdown() and not IsMounted() and cur_speed > 0 then
                    local delta_time = ( frameTime - aura_env.last ) 
                    Player.movement_yds = Player.movement_yds + ( cur_speed * delta_time )
                    Player.movement_t = Player.movement_t + delta_time
                    Player.movement_rate = Player.movement_yds / Player.movement_t
                else
                    Player.movement_yds = 0
                    Player.movement_t = 0
                    Player.movement_rate = 0
                end
                
                Player.moving = Player.movement_t >= 1.25
            end
            
            aura_env.fast = false
            aura_env.last = frameTime                   
            fullUpdate = true
        end
        
        aura_env.LBG = aura_env.LBG or LibStub( "LibCustomGlow-1.0" )
        local LBG = aura_env.LBG
        
        
        local jeremy = aura_env.jeremy_update or {}
        local compression_value = 1000
        local spellRaw = function ( name )
            local raw = jeremy.raw[ name ] or 0 
            raw = raw * compression_value
            return raw
        end
        jeremy.raw = jeremy.raw or {}
        jeremy.rank = {}
        local spells = aura_env.spells
        local actionlist = {}
        local actionhash = {}
        local default_action = Player.default_action
        local rate_time = ( aura_env.base_gm and Player.action_modifier / aura_env.base_gm ) or 1
        aura_env.action_cache = aura_env.action_cache or {}
        local action_set = function( tbl )
            if not tbl.name then return end
            tbl.cb            = tbl.cb or spells[ tbl.name ]
            tbl.raw           = tbl.raw or 0
            tbl.damage        = tbl.damage or 0
            tbl.healing       = tbl.healing or 0
            tbl.group_healing = tbl.group_healing or 0 
            tbl.cooldown      = tbl.cooldown or 0
            tbl.cd_remains    = tbl.cooldown_remains or 0
            tbl.start_cd      = tbl.starts_cooldown or {}
            tbl.execute_time  = max( 0, tbl.execute_time or 0 )
            tbl.cost          = tbl.cost or 0
            tbl.chi_cost      = tbl.chi_cost or 0
            tbl.t_amp         = tbl.t_amp or 1.0
            tbl.delay         = max( 0, tbl.delay or 0 )
            tbl.mastery_break = tbl.mastery_break or false            
            local raw_comp = tbl.raw / compression_value
            jeremy.raw[ tbl.name ] = raw_comp > 1 and floor( raw_comp ) or raw_comp 
            if not tbl.background then
                local dpet = tbl.raw / max( 1, 1 + ( tbl.execute_time + tbl.delay )  * rate_time ) 
                tbl.d_time = dpet - tbl.cost
                tbl.d_cost = dpet / max( 1, 1 + tbl.cost )
                
                local index = actionhash[ tbl.name ] or #actionlist+1
                actionlist[ index ] = tbl
                actionhash[ tbl.name ] = index
            end
            aura_env.action_cache[ tbl.name ] = tbl
        end
        
        if spec == 0 then
            return
        end
        
        local targets_tod_range = 0
        local targetList = {}
        local demiseList = {}
        local healer_targets = {}
        
        if fullUpdate then
            
            profilerStart()
            
            -- Update these values also in the worker thread
            Player.health_deficit = UnitHealthMax( "player" ) - UnitHealth( "player" )
            Player.eps        = GetPowerRegen()
            Player.mana       = UnitPower( "player" , 0 )
            Player.energy     = UnitPower( "player" , 3 )
            Player.energy_max = UnitPowerMax( "player", 3 )
            Player.chi        = UnitPower( "player" , 12 )
            Player.chi_max    = UnitPowerMax( "player", 12 )
            Player.stagger    = UnitStagger( "player" ) or 0
            
            Player.primary_stat = select( 2, UnitStat( "player", 2 ) )
            
            if Player.needsFullUpdate then
                ScanEvents( "UNIT_AURA_FULL_UPDATE", "player" )
            end            
            
            local gcd_start = GetSpellCooldown( 61304 )
            
            if gcd_start > 0 then
                Player.gcd_duration = gcdDuration()
                Player.gcd_remains = Player.gcd_duration - ( frameTime - gcd_start )    
            else
                Player.gcd_duration = 0
                Player.gcd_remains = 0
            end
            
            if Player.eps > 0 then
                Player.mana       = Player.mana + ( Player.eps * Player.gcd_remains )
                Player.energy     = Player.energy + ( Player.eps * Player.gcd_remains )
                Player.energy_ttm = ( Player.energy_max - Player.energy ) / Player.eps      
            end
            
            jeremy.monk_eps         = Player.eps
            jeremy.monk_mana        = Player.mana
            jeremy.monk_energy      = Player.energy
            jeremy.monk_energy_max  = Player.energy_max
            jeremy.monk_chi         = Player.chi
            jeremy.monk_chi_max     = Player.chi_max
            
            local _, _, _, channel_start, channel_end, _, _, channelID = UnitChannelInfo( "player" )
            
            Player.channel_start = channel_start
            Player.channel_end = channel_end
            Player.channel_id = channelID
            
            if not channelID then
                aura_env.tick_update = nil
            end
            
            Player.is_pvp = UnitIsPlayer( "target" ) and aura_env.validTarget(  "target" )
            
            profilerEnd( "Update Unit Info" )
            
            local ParseAuras = function( Enemy, unitID )
                
                -- Faux auras
                aura_env.targetAuras[ unitID ] = {}
                aura_env.targetAuras[ unitID ][ "priority_check" ] = { amp = Enemy.priority_modifier, expire = frameTime + 3600 }
                
                if spec == aura_env.SPEC_INDEX[ "MONK_BREWMASTER" ] then
                    local threat_status = UnitThreatSituation( "player", unitID ) or 0
                    aura_env.targetAuras[ unitID ][ "threat_check" ] = { 
                        amp = ( threat_status < 3 and 2.0 or 1.0 ), 
                        expire = frameTime + 3600 
                    }
                end
                
                -- Windwalker Specific
                if spec == aura_env.SPEC_INDEX[ "MONK_WINDWALKER" ] then
                    
                    -- Mark of the Crane
                    Enemy.auraExists( 228287, function( auraData )
                            if auraData.sourceUnit == "player" then
                                Player.motc_targets = Player.motc_targets + 1
                                return true
                            end
                    end )
                    
                    -- Shadowflame Vulnerability
                    Enemy.auraExists( 411376, function( auraData )
                            if auraData.sourceUnit == "player" then
                                Player.sfv_targets = Player.sfv_targets + 1
                                return true
                            end    
                    end )       
                    
                    -- Keefer's Skyreach
                    Enemy.auraExists( 393047, function( auraData )
                            if auraData.sourceUnit == "player" then
                                local expires = auraData.expirationTime
                                if expires == 0 then
                                    expires = frameTime + 3600
                                end                
                                -- 0 amplifier for tracking purposes
                                aura_env.targetAuras[ unitID ][ auraData.spellId ] = { 
                                    amp = 0, 
                                    expire = expires 
                                }
                                return true    
                            end    
                    end )              
                    
                    -- Fae Exposure / Jadefire Brand
                    Enemy.auraExists( { 356773, 395414 }, function( auraData )
                            if auraData.sourceUnit == "player" then
                                local expires = auraData.expirationTime
                                if expires == 0 then
                                    expires = frameTime + 3600
                                end
                                
                                Player.jfh_targets = Player.jfh_targets + 1
                                Player.jfh_dur_total = max( 0, Player.jfh_dur_total + ( expires - frameTime ) )
                                aura_env.targetAuras[ unitID ][ auraData.spellId ] = { 
                                    amp = 1.12, 
                                    expire = expires 
                                }
                                return true
                            end    
                    end )
                end
                
                -- Brewmaster Specific
                if spec == aura_env.SPEC_INDEX[ "MONK_BREWMASTER" ] then
                    
                    -- Weapons of Order Debuff
                    Enemy.auraExists( { 312106, 387179 }, function( auraData )
                            if auraData.sourceUnit == "player" then
                                local expires = auraData.expirationTime
                                if expires == 0 then
                                    expires = frameTime + 3600
                                end
                                
                                local woo_count = auraData.applications or 0
                                local woo_amp = 1 + ( 0.08 * woo_count )
                                aura_env.woo_best = max( aura_env.woo_best, woo_count )
                                Player.woo_targets = Player.woo_targets + 1
                                Player.woo_dur_total = max( 0, Player.woo_dur_total + ( expires - frameTime ) )
                                aura_env.targetAuras[ unitID ][ auraData.spellId ] = { 
                                    amp = woo_amp, 
                                    expire = expires 
                                }
                                return true
                            end    
                    end )    
                    
                    -- Keg Smash
                    Enemy.auraExists( 121253, function( auraData )
                            if auraData.sourceUnit == "player" then
                                Player.ks_targets = Player.ks_targets + 1
                                return true
                            end    
                    end ) 
                    
                    -- Breath of Fire
                    Enemy.auraExists( 123725, function( auraData )
                            if auraData.sourceUnit == "player" then
                                Player.bof_targets = Player.bof_targets + 1
                                return true
                            end    
                    end )         
                end
                
                -- Generic
                
                -- Bonedust Brew
                Enemy.auraExists( { 325216, 386276 }, function( auraData )
                        if auraData.sourceUnit == "player" then
                            local expires = auraData.expirationTime
                            if expires == 0 then
                                expires = frameTime + 3600
                            end
                            
                            aura_env.bdb_dur_total = max( 0, aura_env.bdb_dur_total + ( expires - frameTime ) )
                            Player.bdb_targets = Player.bdb_targets + 1
                            aura_env.targetAuras[ unitID ][ auraData.spellId ] = { 
                                amp = aura_env.bdb_amp(), 
                                expire = expires 
                            }
                            return true
                        end    
                end )
                
                -- Others defined in Init
                for id, aura_amp in pairs( aura_env.aura_amps ) do
                    local copies = 0
                    Enemy.auraExists( id, function( auraData )
                            local expires = auraData.expirationTime
                            if expires == 0 then
                                expires = frameTime + 3600
                            end         
                            
                            if copies > 0 then
                                aura_env.targetAuras[ unitID ][ id ] = { 
                                    amp = aura_env.targetAuras[ unitID ][ id ].amp * aura_amp.modifier, 
                                    expire = min( aura_env.targetAuras[ unitID ][ id ].expires, expires ) 
                                }
                            else
                                aura_env.targetAuras[ unitID ][ id ] = { 
                                    amp = aura_amp.modifier, 
                                    expire = expires 
                                }
                            end
                            copies = copies + 1
                            if copies >= aura_amp.copies then
                                return true
                            end
                    end )
                end
            end
            
            aura_env.combatHealthRemaining = 0
            aura_env.targetHealthRemaining = 0
            
            aura_env.in_keystone = select( 10, GetInfo() ) == LE_SCENARIO_TYPE_CHALLENGE_MODE 
            
            local UpdateTargets = function()
                
                local count = 0
                local fight_remains = 0
                local finalBoss = false
                
                aura_env.boss_lockdown = false
                aura_env.woo_best = 0
                aura_env.bdb_dur_total = 0
                
                Player.motc_targets = 0
                Player.jfh_targets = 0
                Player.jfh_dur_total = 0
                Player.bdb_targets = 0
                Player.ks_targets = 0
                Player.bof_targets = 0
                Player.sfv_targets = 0
                Player.woo_targets = 0
                aura_env.targetAuras = {}
                
                healer_targets = {}
                
                if spec == aura_env.SPEC_INDEX["MONK_MISTWEAVER"]  then
                    -- Skip this loop for efficiency if not MW Spec
                    
                    for it in WA_IterateGroupMembers() do
                        if  UnitIsDead( it ) == false and CheckInteractDistance( it, 1 ) then
                            local deficit = UnitHealthMax( it ) - UnitHealth( it ) + UnitGetTotalHealAbsorbs( it )
                            
                            if deficit > 0 then -- Valid healing target
                                healer_targets[ #healer_targets + 1 ] = {
                                    deficit = deficit,
                                    unitID = it,
                                }
                            end
                        end
                    end
                end
                
                local targetLimit = 10
                local configLimit = aura_env.config.target_limit
                if configLimit then
                    if configLimit == 1 then
                        targetLimit = 5
                    elseif configLimit == 2 then
                        targetLimit = 10
                    elseif configLimit == 3 then
                        targetLimit = 15
                    else
                        targetLimit = 20
                    end
                end
                
                local TargetFilter = function()
                    
                    local validTargets = {}
                    local checkTod = aura_env.getCooldown( 322109 ) == 0 and aura_env.config.tod_glow > 1
                    
                    for _, nameplateframe in pairs( GetNamePlates() ) do
                        
                        local unitID = nameplateframe.namePlateUnitToken
                        local unitGUID = UnitGUID( unitID )
                        
                        if unitGUID == UnitGUID( "target" ) then
                            unitID = "target"
                        end
                        
                        local glowTod = false
                        
                        if aura_env.validTarget( unitID ) then
                            
                            local enemy = aura_env.GetEnemy( unitGUID )
                            
                            enemy.unitID = unitID
                            enemy.range = aura_env.unitRange( unitID )
                            
                            -- Update BigWig Intermission Timers
                            local intermission = nil
                            for k, v in pairs( aura_env.BW_intermission_timers ) do
                                local remaining = v.expire - frameTime
                                if v.encounterId ~= aura_env.encounter_id or remaining <= 0 then
                                    aura_env.BW_intermission_timers[ k ] = nil
                                elseif UnitGUID( v.unitid ) == unitGUID then
                                    intermission = ( intermission and min( intermission, remaining ) ) or remaining
                                end
                            end
                            enemy.intermission = intermission
                            
                            local excluded = ( enemy.priority_modifier == 0 )
                            
                            if not excluded and enemy.lastHealth then
                                excluded = enemy.lastHealth < 0.01
                            end   
                            
                            if not excluded then
                                excluded = enemy.range > 8
                            end          
                            
                            if not excluded then
                                if enemy.needsFullUpdate then
                                    ScanEvents( "UNIT_AURA_FULL_UPDATE", unitID )
                                end
                                excluded = ( next( enemy.auraExclusions ) ~= nil )
                            end
                            
                            if excluded then
                                aura_env.targetAuras[unitID] = {}
                                aura_env.targetAuras[unitID]["priority_check"] = { amp = ( unitID == "target" and 0.01 ) or 0, expire = frameTime + 3600 }
                            else
                                
                                -- ToD off CD and option enabled
                                if checkTod then
                                    -- Valid ToD Target
                                    if ( enemy.healthPct < 0.15 and Player.talent.improved_touch_of_death.ok and aura_env.config.tod_glow < 3 ) 
                                    or UnitHealth( unitID ) < UnitHealthMax( "player" ) then
                                        glowTod = true
                                        targets_tod_range = targets_tod_range + 1
                                    end
                                end
                                
                                validTargets[ #validTargets + 1 ] = enemy
                                targetList[ #targetList + 1 ] =  enemy.npcid                               
                            end
                            
                        end
                        
                        if nameplateframe then
                            if glowTod then 
                                LBG.PixelGlow_Start( nameplateframe, { 1, 0, 0, 1 } )
                            else
                                LBG.PixelGlow_Stop( nameplateframe )
                            end
                        end    
                        
                    end      
                    
                    if #validTargets > targetLimit then
                        sort( validTargets, function( l, r ) 
                                if l.unitID == "target" then
                                    return true
                                elseif r.unitID == "target" then
                                    return false
                                elseif l.isBoss and not r.isBoss then
                                    return true
                                elseif r.isBoss and not l.isBoss then
                                    return false
                                elseif l.ttd and r.ttd then
                                    return l.ttd > r.ttd
                                else
                                    return ( l.lastHealth or 1 ) > ( r.lastHealth or 1 )
                                end
                        end )
                    end
                    
                    return validTargets
                end
                
                for _, enemy in pairs( TargetFilter() ) do
                    
                    if not aura_env.boss_lockdown then 
                        
                        if enemy.isBoss then
                            
                            aura_env.boss_lockdown = true
                            
                            if not finalBoss and aura_env.in_keystone then
                                local steps = select( 3, GetStepInfo() )
                                
                                if steps then
                                    local _, _, _, _, total, _, _, current = GetCriteriaInfo( steps )
                                    
                                    if current then
                                        current = tonumber( sub( current, 1, len( current ) - 1 ) ) or 0
                                        if ( current / total ) > 0.99 then
                                            finalBoss = true
                                        end
                                    end
                                end
                            end
                        end
                    end    
                    
                    count                   = count + 1
                    aura_env.combatHealthRemaining   = aura_env.combatHealthRemaining + enemy.healthActual
                    fight_remains           = max( enemy.ttd or 0, fight_remains )
                    
                    local demise = max( 1, floor( enemy.ttd or 1 ) )
                    demiseList[ demise ] = ( demiseList[ demise ] or 0 ) + 1
                    
                    if enemy.unitID == "target" then
                        aura_env.targetHealthRemaining = enemy.healthActual
                    end
                    
                    ParseAuras( enemy, enemy.unitID )
                    
                    if count >= targetLimit then
                        break
                    end
                end
                
                if finalBoss then
                    aura_env.fight_remains = 3600
                else
                    if fight_remains > 0 then
                        aura_env.fight_remains = max( 1, floor( fight_remains + 0.5 ) )
                    else
                        aura_env.fight_remains = 300
                    end
                end
                
                sort( healer_targets, function( l, r ) 
                        return l.deficit > r.deficit 
                end)
                
                return max( 1, count )
            end
            
            if not aura_env.target_update or aura_env.target_update < frameTime - 1 then
                profilerStart()
                
                -- Nameplate iterator 
                aura_env.target_count = UpdateTargets()
                aura_env.healer_targets = healer_targets
                
                profilerEnd( "UpdateTargets()" )
                
                -- Force ST Config Option
                if aura_env.config.targetting == 2 then
                    aura_env.target_count = 1         
                end                
                
                profilerStart()
                
                -- Initialize one-time pull data
                if aura_env.target_count > 1 then
                    aura_env.pull_hash = aura_env.hashEnemyList( targetList ) -- Generate unique pull ID
                    aura_env.pull_data = aura_env.get_pull_data( aura_env.pull_hash ) -- Initialize pull data
                    --aura_env.nextPullListener( aura_env.pull_hash )
                end
                
                profilerEnd( "Hash Pull Data" )
                profilerStart()
                
                -- Time based spawn / demise
                aura_env.raid_events = aura_env.EventTimers( demiseList )       
                
                profilerEnd( "Update Event Timers" )
                
                aura_env.target_update = frameTime
            end
            
        end
        
        local t_spells = {}
        for name, action in pairs( spells ) do
            t_spells[ #t_spells + 1 ] = {
                name = name,
                action = action,
            }
        end      
        local n_spells = #t_spells
        
        if n_spells > 0 and ( fullUpdate or not aura_env.actionlist_update or aura_env.actionlist_update < frameTime - ( 0.5 / n_spells ) )then
            
            aura_env.actionlist_update = frameTime
            
            local serenity = ( spec == aura_env.SPEC_INDEX[ "MONK_WINDWALKER" ] and Player.findAura( 152173 ) ) or nil
            local brewmaster_dmg_ratio = max( 0.01, aura_env.config.brewmaster_ratio )
            local brewmaster_heal_ratio = max( 0.01, 1 - aura_env.config.brewmaster_ratio )
            
            debugprofilestart()
            
            local cpu_target = aura_env.config.cpu_target or 1.5 -- target CPU processing time in miliseconds
            
            if aura_env.rank_cpu_average then
                cpu_target = cpu_target - aura_env.rank_cpu_average
            end
            
            local process_trees = 5
            
            if aura_env.action_cpu_average then
                process_trees = max( 1, floor( cpu_target / aura_env.action_cpu_average ) )
            end
            
            if not InCombatLockdown() then
                -- limited to 5 out of combat
                process_trees = min( process_trees, 5 )
            end
            
            local debug_process_min = nil
            local debug_process_max = nil
            if not aura_env.spell_range_min or aura_env.spell_range_min >= n_spells then
                aura_env.spell_range_min = 1
            end
            aura_env.spell_range_max = ( aura_env.spell_range_min + process_trees )
            
            for spell_it, _spell in ipairs( t_spells ) do
                
                local name = _spell.name
                local action = _spell.action
                
                local continue = false
                if spell_it < aura_env.spell_range_min or spell_it > aura_env.spell_range_max then
                    if aura_env.action_cache[ name ] then
                        action_set( aura_env.action_cache[ name ] )
                        continue = true
                    end
                end
                
                if not continue then
                    
                    debug_process_min = debug_process_min or spell_it
                    debug_process_max = spell_it
                    
                    local spellID = action.spellID
                    local action_type = action.type or "damage"
                    
                    if action_type == "damage_buff"
                    or action_type == "healing_buff" then
                        local pct = ( type( action.pct ) == "function" and action.pct() or action.pct ) or 0
                        pct = max( 0, pct )
                        
                        local active = Player.findAura( spellID )
                        local remains = ( active and active.remaining or 0 )
                        local refresh_behavior = aura_env.buff_refresh_behavior[ action.refresh_behavior or "DURATION" ]
                        local base_duration = ( type( action.base_duration ) == "function" and action.base_duration() or action.base_duration ) or 0
                        local buff_duration = ( type( action.duration ) == "function" and action.duration( base_duration ) or action.duration ) or 0
                        
                        -- TODO: Proper Debuffs
                        if not action.debuff then
                            if active then 
                                if refresh_behavior == aura_env.buff_refresh_behavior[ "DISABLED" ] then
                                    buff_duration = 0
                                else
                                    if refresh_behavior == aura_env.buff_refresh_behavior[ "DURATION" ] then
                                        buff_duration = buff_duration - remains
                                    elseif refresh_behavior == aura_env.buff_refresh_behavior[ "PANDEMIC" ] then
                                        buff_duration = buff_duration + min( 0.3 * buff_duration, remains )
                                    elseif refresh_behavior == aura_env.buff_refresh_behavior[ "MAX" ] then
                                        buff_duration = max( buff_duration, remains )
                                        -- else 
                                        -- Refresh to given duration plus remaining duration
                                        -- ( buff_duration = buff_duration )
                                    end
                                end
                            end
                            
                            buff_duration = min( aura_env.fight_remains, buff_duration )
                        end
                        
                        local raw = 0 
                        local sequence_t = 0
                        for _, sequence_name in pairs( Player.action_sequence ) do
                            local cached_action = aura_env.action_cache[ sequence_name ]
                            if cached_action then
                                local cached_result = spells[ sequence_name ] and spells[ sequence_name ].result
                                if cached_result then
                                    raw = raw + ( action_type == "damage_buff" and cached_result.damage or cached_result.self_healing + cached_result.group_healing )
                                    sequence_t = sequence_t + cached_action.execute_time
                                end
                            end
                        end
                        raw = raw / ( sequence_t + 1 )
                        raw = raw * pct * math.max( 1, buff_duration )
                        raw = math.max ( 0, raw )
                        
                        if not action.ready or not action.ready() then
                            raw = 0
                        end
                        
                        action.result = {
                            callback                = action,
                            ticks                   = nil,
                            target_count            = nil,
                            damage                  = raw,
                            self_healing            = 0,
                            group_healing           = 0,
                            mitigation              = 0,
                            crit_rate               = 0,
                            crit_mod                = 1,
                            critical_damage         = 0,
                            critical_healing        = 0,
                            critical_group_healing  = 0,
                        }
                        
                        action_set({
                                type = action_type,
                                name = name,
                                raw = raw,
                                cost = 0,
                                execute_time = 0,
                                background = true,
                        })
                        
                    elseif spellID ~= nil then
                        
                        -- Cache AP/SP values
                        -- these sometimes change in PvP combat so we'll cache that as well
                        if not action.pve_ap_value and not Player.is_pvp then
                            action.pve_ap_value = ( type( action.ap ) == "function" and action.ap() or action.ap ) or 0
                        elseif not action.pvp_ap_value and Player.is_pvp then
                            action.pvp_ap_value = ( type( action.ap ) == "function" and action.ap() or action.ap ) or 0
                        end
                        
                        if not action.pve_sp_value and not Player.is_pvp then
                            action.pve_sp_value = ( type( action.sp ) == "function" and action.sp() or action.sp ) or 0
                        elseif not action.pvp_sp_value and Player.is_pvp then
                            action.pvp_sp_value = ( type( action.sp ) == "function" and action.sp() or action.sp ) or 0
                        end
                        
                        local ap      = Player.is_pvp and action.pvp_ap_value or action.pve_ap_value
                        local sp      = Player.is_pvp and action.pvp_sp_value or action.pve_sp_value
                        local ticks   = ( type( action.ticks ) == "function" and action.ticks() or action.ticks ) or 1
                        
                        local tooltip = 
                        max( ( action.action_multiplier ~= nil and 1 or 0 ), ticks * ( sp > 0 and ( sp * aura_env.spell_power ) or ( ap * Player.ability_power ) ) )
                        
                        local action_targets    = max( 1, min( 20, ( action.target_count and action.target_count() ) or 1 ) )
                        local action_cooldown   = aura_env.actionBaseCooldown( action )
                        local action_cd_remains = aura_env.getCooldown( spellID )
                        local action_delay      = 0
                        local start_cooldown    = action.start_cooldown or {}
                        local combo_base        = action.combo_base
                        
                        if action.combo and not action.combo_base then
                            for base_action, combos in pairs( aura_env.combo_list ) do 
                                for _, combo in pairs( combos ) do 
                                    if combo == name then
                                        combo_base = base_action
                                        break
                                    end
                                end
                                if combo_base then
                                    break
                                end
                            end
                            action.combo_base = combo_base
                        end
                        
                        if combo_base and not start_cooldown[ combo_base ] then
                            start_cooldown[ #start_cooldown + 1 ] = combo_base
                        end
                        
                        local ready = action.background or IsSpellKnown( action.replaces or spellID )
                        
                        if ready and action.ready then
                            ready = action.ready()
                        end
                        
                        local mastery = 1
                        local mastery_break = false
                        
                        if action.ww_mastery then
                            if Player.last_combo_strike ~= spellID then
                                mastery = Player.mast_bonus
                            else
                                mastery = 1
                                mastery_break = true
                            end
                        end
                        
                        local execute_time = action.execute_time and action.execute_time() or aura_env.base_execute_time( spellID ) 
                        local chi = action.chi and action.chi() or aura_env.chi_base_cost( action.replaces or spellID )
                        local energy_cost = action.energy and action.energy() or aura_env.energy_base_cost( action.replaces or spellID )
                        local mana_cost = action.mana and action.mana() or aura_env.mana_base_cost( action.replaces or spellID )
                        local cost = ( energy_cost / Player.eps )
                        
                        if spec == aura_env.SPEC_INDEX["MONK_WINDWALKER"]  then
                            cost = chi
                        elseif spec == aura_env.SPEC_INDEX["MONK_MISTWEAVER"]  then
                            cost = ( mana_cost / Player.eps )
                        end
                        
                        action.base_cost = cost or 0
                        action.base_execute_time = execute_time or 0
                        
                        if action.combo and aura_env.fight_remains < execute_time then
                            ready = false
                        end
                        
                        if not ready then
                            action_set( {
                                    type = action_type,
                                    name = name,
                                    raw = 0,
                                    cost = cost,
                                    execute_time = execute_time,
                            } )
                            action.result = nil
                        end
                        
                        if ready and action.skip_calcs then
                            action_set( {
                                    type = action_type,
                                    name = name,
                                    raw = 1,
                                    cost = cost,
                                    execute_time = execute_time,
                                    chi_cost = chi,
                                    energy_cost = energy_cost,
                                    mana_cost = mana_cost,                            
                            } )
                            action.result = nil
                        elseif ready then 
                            
                            -- Check if we're channeling and add channel latency
                            if Player.channel_id and not action.background then
                                local latency = Player.channel_latency or 0
                                if Player.channel_id == 101546 and action.usable_during_sck then
                                    latency = 0
                                end                            
                                action_delay = max( action_delay, latency )
                            end
                            
                            -- Action is not ready but is also not a background action
                            if not action.background then --and not IsUsableSpell( spellID ) then
                                
                                local usable_in = 0
                                
                                -- Add energy regen to action delay if low on resources
                                if energy_cost > 0 and Player.energy < energy_cost then
                                    local energy_delta = energy_cost - Player.energy
                                    usable_in = ( energy_delta / Player.eps )
                                end
                                
                                -- Add cooldown time to action delay if cooldown is shorter than GCD
                                local cd_after_gcd = action_cd_remains - Player.gcd_remains
                                local charges = GetSpellCharges( spellID )
                                if cd_after_gcd > 0 and ( not charges or charges == 0 ) then
                                    usable_in = max( usable_in, cd_after_gcd )
                                end
                                
                                action_delay = max( action_delay, usable_in )
                                
                            end
                            
                            -- Stagger
                            local stagger_reduction = 0
                            if action.reduce_stagger and type( action.reduce_stagger ) == "function" then
                                stagger_reduction = action.reduce_stagger()
                                stagger_reduction = min( stagger_reduction, Player.stagger ) -- Limited to current stagger
                            end
                            
                            -- Mitigation
                            local mitigation = 0
                            if action.mitigate and type( action.mitigate ) == "function" then
                                mitigation = action.mitigate()
                            end
                            
                            -- Shuffle
                            local shuffle_time_granted = 0
                            if spec == aura_env.SPEC_INDEX[ "MONK_BREWMASTER" ] then
                                local shuffle = Player.findAura( 215479 )
                                
                                if action.grant_shuffle 
                                and Player.talent.shuffle.ok 
                                and ( not shuffle or ( shuffle.remaining - Player.gcd_remains ) <= 1 ) then
                                    
                                    shuffle_time_granted 
                                    = ( type( action.grant_shuffle ) == "function" and action.grant_shuffle() or action.grant_shuffle )
                                    
                                    if shuffle_time_granted > 0 then    
                                        
                                        local dtps = Player.recent_dtps
                                        
                                        -- Add fake damage out of combat so that Brewmasters start pulls correctly
                                        if not InCombatLockdown() then
                                            dtps = UnitHealthMax( "player" ) * 0.1
                                        end
                                        
                                        local stagger_pct, stagger_target_pct = GetStaggerPercentage( "player" )
                                        local shuffle_pct = ( stagger_target_pct or stagger_pct ) / 100 / ( shuffle and 2 or 1 )
                                        local shuffle_dr = dtps * shuffle_time_granted * shuffle_pct
                                        
                                        mitigation = mitigation + shuffle_dr
                                    end
                                end
                            end
                            
                            -- Action Multiplier
                            tooltip = tooltip * ( action.action_multiplier and action.action_multiplier() or 1 )
                            
                            -- Versatility
                            tooltip = tooltip * Player.vers_bonus
                            
                            -- Cache spec auras
                            -- these sometimes change in PvP so we will cache both
                            if not action.aura_modifier_pve and not Player.is_pvp
                            or not action.aura_modifier_pvp and Player.is_pvp then
                                local total_aura_effect = aura_env.auraEffectForSpell( action.dotID or spellID )
                                
                                if Player.is_pvp then
                                    action.aura_modifier_pvp = total_aura_effect
                                else
                                    action.aura_modifier_pve = total_aura_effect
                                end
                            end
                            
                            tooltip = tooltip * ( Player.is_pvp and action.aura_modifier_pvp or action.aura_modifier_pve )
                            
                            -- Bonus damage and healing not related to ap or sp modifier
                            local bonus_damage = action.bonus_da and action.bonus_da() or 0
                            local bonus_healing = action.bonus_heal and action.bonus_heal() or 0
                            
                            -- Damage value
                            local damage = action_type == "damage" and tooltip or 0
                            damage = ( damage * mastery ) + bonus_damage
                            
                            -- Self-healing value
                            local healing = action_type == "self_heal" and tooltip or 0
                            healing = healing + bonus_healing
                            
                            -- Targeted healing value
                            local group_healing = action_type == "smart_heal" and tooltip or 0
                            group_healing = group_healing + bonus_healing
                            
                            -- Critical modifiers
                            local crit_damage        = 0
                            local crit_healing       = 0
                            local crit_group_healing = 0
                            local crit_rate          = 0
                            local crit_mod           = 0
                            
                            if action.may_crit then
                                crit_rate = action.critical_rate and action.critical_rate() or Player.crit_bonus
                                crit_mod = action.critical_modifier and action.critical_modifier() or 1
                                
                                if crit_rate < 1.0 then
                                    -- Keefer's Skyreach
                                    crit_rate = min( 1, crit_rate + aura_env.skyreach_modifier( action ) )
                                end
                                
                                if Player.is_pvp then
                                    local pvp_crit_modifier = Player.spell.pvp_enabled.effectN( 3 ).mod
                                    crit_mod = crit_mod * pvp_crit_modifier
                                end
                                
                                local crit_effect   = crit_rate * crit_mod
                                crit_damage         = damage * crit_effect
                                crit_healing        = healing * crit_effect
                                crit_group_healing  = group_healing * crit_effect
                                
                                damage          = damage + crit_damage
                                healing         = healing + crit_healing
                                group_healing   = group_healing + crit_group_healing
                            end
                            
                            -- Target Multiplier
                            local target_multiplier = 1
                            
                            if action_type == "smart_heal" then
                                target_multiplier = 0
                                for t_it = 1, action_targets do
                                    local target = aura_env.healer_targets[ t_it ]
                                    target_multiplier = target_multiplier + ( action.target_multiplier and action.target_multiplier( target ) or 1 )
                                end
                            elseif action.target_multiplier then
                                target_multiplier = action.target_multiplier( action_targets )
                            end
                            
                            -- Target Auras
                            local temporary_amplifiers = global_modifier( action, action_delay ) * targetAuraEffect( action, action_delay )
                            
                            -- Cache curent player amplifier
                            if name == default_action then
                                Player.action_modifier = temporary_amplifiers
                            end
                            
                            -- Add spawn delta
                            -- weight of holding expensive CDs for upcoming add phase
                            local spawn_delta = 1
                            
                            if action.target_multiplier 
                            and action_type == "damage"
                            and not action.background 
                            and ( not Player.channel_id or Player.channel_id ~= spellID )
                            and name ~= "touch_of_death" then
                                local cooldown = aura_env.actionBaseCooldown( action )
                                if cooldown > 0 then
                                    for _, raid_event in pairs( aura_env.raid_events ) do
                                        local error = ( 1 - aura_env.error_margin )
                                        local count = raid_event.count
                                        local t = max( 1, floor( raid_event.adds_in - Player.gcd_remains ) )
                                        if count > action_targets and cooldown > t and t > action_delay then
                                            local delta_tm 
                                            = action.target_multiplier( count ) / action.target_multiplier( action_targets )
                                            local delta_fm 
                                            = aura_env.forwardModifier( spells[name], t ) / aura_env.forwardModifier( spells[name] )
                                            local delta_cm 
                                            = t / cooldown
                                            spawn_delta = min( spawn_delta, 1 / ( delta_tm / delta_fm / delta_cm / error ) )
                                        end
                                    end
                                end
                            end
                            
                            damage = damage * target_multiplier * temporary_amplifiers * spawn_delta
                            healing = healing * temporary_amplifiers
                            group_healing = group_healing * target_multiplier * temporary_amplifiers
                            
                            -- Expel Harm
                            if name == "expel_harm" then
                                -- Only Healing config option for Brewmaster
                                if spec ~= 1 or aura_env.config.eh_mode ~= 2 then
                                    local eh_damage = max( 1, 0.1 * healing )
                                    damage = damage + eh_damage
                                end
                            end             
                            
                            -- AA Loss
                            if action.interrupt_aa then
                                
                                local mh_dmg = Player.mh_wdps * Player.vers_bonus
                                local oh_dmg = Player.oh_wdps * Player.vers_bonus
                                
                                local mh_miss = oh_dmg > 0 and 0.81 or 1
                                local oh_miss = 0.81
                                
                                local mainSpeed, offSpeed = UnitAttackSpeed( "player" );
                                
                                mainSpeed = mainSpeed or 0
                                offSpeed = offSpeed or 0 
                                
                                local mh_loss = ( mainSpeed > 0 and mh_dmg * mh_miss / mainSpeed ) or 0
                                local oh_loss = ( offSpeed > 0  and oh_dmg * oh_miss / offSpeed ) or 0
                                
                                local swings_lost = 0
                                
                                if mainSpeed > 0 then 
                                    swings_lost = swings_lost + ( execute_time / mainSpeed )
                                end
                                
                                if offSpeed > 0 then
                                    swings_lost = swings_lost + ( execute_time / offSpeed )
                                end
                                
                                -- Thunderfist
                                if spec == aura_env.SPEC_INDEX[ "MONK_WINDWALKER" ] then
                                    local thunderfist = Player.findAura( 242387 )
                                    
                                    if thunderfist then
                                        local tf_stack_value = spellRaw( "thunderfist_single" )
                                        mh_loss = mh_loss + ( min( swings_lost, thunderfist.stacks ) * tf_stack_value )
                                    end
                                end
                                -- ----------------------
                                
                                -- Press the Advantage
                                if spec == aura_env.SPEC_INDEX[ "MONK_BREWMASTER" ] then
                                    if Player.talent.press_the_advantage.ok then
                                        local pta_value = spellRaw( "press_the_advantage" )
                                        pta_value = pta_value + max( spellRaw( "pta_rising_sun_kick" ), spellRaw( "pta_keg_smash" ) / 10 )
                                        
                                        mh_loss = mh_loss + ( swings_lost * pta_value )
                                    end
                                end
                                -- ----------------------
                                
                                local aa_loss = mh_loss + oh_loss
                                
                                damage = max( 0, damage - ( aa_loss * execute_time ) )
                            end
                            
                            -- -----------------------------------------------------
                            
                            local result = {
                                callback                = action,
                                ticks                   = ticks,
                                target_count            = action_targets,
                                damage                  = damage,
                                self_healing            = healing,
                                group_healing           = group_healing,
                                mitigation              = mitigation,
                                crit_rate               = crit_rate,
                                crit_mod                = crit_mod,
                                critical_damage         = crit_damage,
                                critical_healing        = crit_healing,
                                critical_group_healing  = crit_group_healing,
                                execute_time            = execute_time
                            }
                            
                            -- Cache result
                            action.result = result
                            
                            -- Action post-process events
                            aura_env.actionPostProcessor( result )
                            
                            damage = result.damage
                            healing = result.self_healing
                            group_healing = result.group_healing
                            mitigation = result.mitigation
                            crit_rate = result.crit_rate
                            crit_mod = result.crit_mod
                            
                            -- Ability triggers ( GotD, Resonant Fists, etc., also used for combos )
                            local applyTriggerSpells = function( )
                                local damage_out, healing_out, group_heal_out = 0, 0, 0
                                local trigger_chi_gain = 0
                                local driver = action
                                local driverName = combo_base or name
                                
                                driver.trigger = driver.trigger or {}
                                driver.tick_trigger = driver.tick_trigger or {}
                                
                                if driver.ww_mastery then
                                    driver.trigger["hit_combo"] = ( not mastery_break )
                                end
                                
                                if driver.resonant_fists then
                                    driver.tick_trigger["resonant_fists"] = true
                                end
                                
                                if driver.grant_shuffle then
                                    driver.trigger["quick_sip_1s"] = ( shuffle_time_granted > 0 )
                                end
                                
                                local trigger_spells = {}
                                local trigger_exists = {}
                                local trigger_pushback = function( spell, enabled, periodic, recursive_callback )
                                    
                                    local _driver = recursive_callback and spells[ recursive_callback ] or driver
                                    local _driverName = recursive_callback or driverName
                                    
                                    trigger_exists[ spell.."-".._driverName ] = true
                                    
                                    if _driver.result then
                                    
                                        if type( enabled ) == "function" then
                                            enabled = enabled( driverName )
                                        end
                                        
                                        -- Allow multiple identical triggers
                                        spell = gsub( spell, "%-.*", "" )    
                                        
                                        if enabled 
                                        and spells[ spell ] 
                                        and spellRaw( spell ) > 0 then
                                            local _this = {}
                                            
                                            _this.state = {
                                                -- Pass driver callbacks to trigger
                                                callback_name = _driverName,
                                                callback = _driver,
                                                result = _driver.result,
                                            }
                                            
                                            _this.spell = spell
                                            _this.onTick = periodic
                                            _this.icd = spells[spell].icd or 0
                                            _this.rate = spells[spell].trigger_rate or 1
                                            if type( _this.rate ) == "function" then
                                                _this.rate = _this.rate( driverName )
                                            end
                                            trigger_spells[ #trigger_spells + 1 ] =  _this
                                        end
                                    end
                                end
                                
                                for spell, enabled in pairs( driver.trigger ) do trigger_pushback( spell, enabled, false ) end
                                for spell, enabled in pairs( driver.tick_trigger ) do trigger_pushback( spell, enabled, true ) end
                                
                                -- Recursive triggers
                                local do_recursion = true
                                    while ( do_recursion ) do
                                    do_recursion = false
                                    for _, trigger in pairs( trigger_spells ) do
                                        local spell = spells[ trigger.spell ]
                                        if spell.trigger then
                                            for recursive_trigger, enabled in pairs( spell.trigger ) do
                                                if not trigger_exists[ recursive_trigger.."-"..trigger.spell ] then    
                                                    trigger_pushback( recursive_trigger, enabled, false, trigger.spell )
                                                    do_recursion = true
                                                end
                                            end
                                        end
                                        if spell.tick_trigger then
                                            for recursive_trigger, enabled in pairs( spell.tick_trigger ) do
                                                if not trigger_exists[ recursive_trigger.."-"..trigger.spell ] then
                                                    trigger_pushback( recursive_trigger, enabled, true, trigger.spell )
                                                    do_recursion = true
                                                end
                                            end     
                                        end
                                    end
                                end
                                
                                for _, trigger in pairs( trigger_spells ) do
                                    
                                    local driver = trigger.state.callback
                                    local driverName = trigger.state.callback_name
                                    local result = trigger.state.result
                                    
                                    local tick_damage = result.damage or 0
                                    local tick_healing = result.healing or 0 
                                    local tick_group_heal = result.group_healing or 0
                                    
                                    local total_ticks = ( result.ticks or 1 ) * ( result.target_count or 1 )
                                    local duration = result.execute_time 
                                    local tick_count = ( trigger.icd > 0 and min( total_ticks, trigger.rate * floor( duration / trigger.icd ) ) ) or ( trigger.rate * total_ticks )
                                    
                                    if not trigger.onTick then
                                        tick_count = trigger.rate
                                    end
                                    
                                    local spell = spells[ trigger.spell ]
                                    
                                    -- Spec options
                                    if spec == aura_env.SPEC_INDEX["MONK_BREWMASTER"]  then
                                        if driver.spellID == 100784 then -- Blackout Kick
                                            trigger.state.blackout_combo = true
                                        end        
                                        
                                        if trigger.spell == "quick_sip_1s" then
                                            tick_damage = tick_damage * shuffle_time_granted
                                            tick_healing = tick_healing * shuffle_time_granted
                                            tick_group_heal = tick_group_heal * shuffle_time_granted       
                                        end 
                                    end
                                    
                                    -- Trigger is non-background action with execute time
                                    local trigger_et = spell.time_total or spell.base_execute_time or 0
                                    if trigger_et > 0 and not spell.background then
                                        execute_time = execute_time + trigger_et
                                    end
                                    
                                    -- Trigger has cost
                                    local trigger_cost = spell.cost_total or spell.base_cost or 0
                                    if trigger_cost > 0 then
                                        cost = cost + trigger_cost
                                    end                                
                                    
                                    -- set init trigger CD
                                    local trigger_cd_remains = aura_env.getCooldown( spell.spellID )
                                    
                                    if not spell.background then
                                        -- Trigger is a non-background action with a cooldown
                                        if trigger_cd_remains > 0 then
                                            -- Driver reduces cooldown of trigger
                                            local driver_cdr = driver.reduces_cd and driver.reduces_cd[ trigger.spell ]
                                            if driver_cdr then
                                                if type( driver_cdr ) == "function" then
                                                    driver_cdr = driver_cdr()
                                                end
                                            end
                                            trigger_cd_remains = trigger_cd_remains - max( 0, ( driver_cdr or 0 ) )
                                        end
                                        
                                        if not IsSpellKnown( spell.replaces or spell.spellID ) or trigger_cd_remains > 0 then
                                            tick_damage = 0
                                            tick_healing = 0
                                            tick_group_heal = 0       
                                        end
                                    end
                                    
                                    if tick_damage > 0 then
                                        -- Use future trigger state
                                        if spell.action_multiplier then
                                            local spell_am = spell.action_multiplier()
                                            local am_delta = spell.action_multiplier( trigger.state )
                                            if spell_am > 0 then
                                                am_delta = am_delta / spell_am
                                            end
                                            
                                            tick_damage = tick_damage * am_delta
                                        end
                                        
                                        -- Reevaluate mastery
                                        if spell.ww_mastery and Player.last_combo_strike == spell.spellID then
                                            tick_damage = tick_damage * Player.mast_bonus
                                        end
                                        
                                        -- Because this is a background ability that triggers from another action
                                        -- we need to modify the spawn delta here
                                        if spell.background and spell.target_multiplier then
                                            local t_spawn_delta = 1
                                            local cooldown = aura_env.actionBaseCooldown( driver )
                                            if cooldown > 0 then
                                                for _, raid_event in pairs( aura_env.raid_events ) do
                                                    local error = ( 1 - aura_env.error_margin )
                                                    local count = raid_event.count
                                                    local t = max( 1, floor( raid_event.adds_in - Player.gcd_remains ) )
                                                    if count > action_targets and cooldown > t and t > action_delay then
                                                        local delta_tm 
                                                        = spell.target_multiplier( count ) / spell.target_multiplier( action_targets )
                                                        local delta_fm 
                                                        = aura_env.forwardModifier( spell, t ) / aura_env.forwardModifier( spell )
                                                        local delta_cm 
                                                        = t / cooldown
                                                        t_spawn_delta = min( t_spawn_delta, 1 / ( delta_tm / delta_fm / delta_cm / error ) )
                                                    end
                                                end
                                            end
                                            tick_damage = tick_damage * t_spawn_delta
                                        end
                                    end
                                    
                                    -- Driver is a channeled ability and trigger is not background action
                                    if driver.channeled and not spell.background then
                                        local latency = Player.channel_latency or 0
                                        local use_during_channel = driver.spellID == 101546 and spell.usable_during_sck 
                                        if use_during_channel then
                                            latency = 0
                                            local gcd     = aura_env.gcd( driver.spellID )
                                            local base_et = driver.execute_time and driver.execute_time() or aura_env.base_execute_time( driver.spellID )
                                            execute_time = execute_time - ( base_et - gcd )
                                        end                            
                                        action_delay = max( action_delay, latency )
                                    end
                                    
                                    
                                    -- Trigger reduces cooldown of non-background driver spell
                                    if not driver.background and spell.reduces_cd and spell.reduces_cd[ driverName ] then
                                        local cdr = spell.reduces_cd[ driverName ] 
                                        local cd = aura_env.actionBaseCooldown( driver )
                                        
                                        if type( cdr ) == "function" then
                                            cdr = cdr( trigger.state )
                                        end
                                        
                                        if cd > 0 and cdr > 0 then
                                            local total_cdr = min( cdr, cd - duration )
                                            local mod_rate =  aura_env.actionModRate( driver )
                                            if mod_rate < 1 then
                                                total_cdr = total_cdr * ( 1 - mod_rate )
                                            end
                                            if total_cdr > 0 then
                                                local spell_raw = spellRaw( driverName )
                                                local trigger_raw = spellRaw( trigger.spell )
                                                if spell_raw > trigger_raw then
                                                    tick_damage = tick_damage + ( total_cdr / cd * max( 0, ( damage - tick_damage * tick_count ) ) )
                                                    tick_healing = tick_healing + ( total_cdr / cd * max( 0, ( healing - tick_healing * tick_count ) ) )
                                                    tick_group_heal = tick_group_heal + ( total_cdr / cd * max( 0 , ( group_healing - tick_group_heal * tick_count ) ) )
                                                    trigger_chi_gain = trigger_chi_gain - ( ( chi or 0 ) * total_cdr / cd )
                                                end                                                
                                            end
                                        end
                                    end
                                    
                                    -- Update cooldown information for chained abilities
                                    if action.combo and not spell.background then 
                                        local trigger_cd  = aura_env.actionBaseCooldown( spell )
                                        action_cooldown   = max( action_cooldown, trigger_cd )
                                        action_cd_remains = max ( action_cd_remains, trigger_cd_remains ) 
                                        start_cooldown[ #start_cooldown + 1] = trigger.spell
                                    end
                                    
                                    damage_out     = damage_out + ( tick_damage * tick_count )
                                    healing_out    = healing_out + ( tick_healing * tick_count ) 
                                    group_heal_out = group_heal_out + ( tick_group_heal * tick_count ) 
                                    trigger_chi_gain = trigger_chi_gain + ( tick_count * ( spell.chi_gain and spell.chi_gain() or 0 ) )
                                    
                                end
                                
                                cost          = cost - trigger_chi_gain
                                damage        = damage + damage_out
                                healing       = healing + healing_out
                                group_healing = group_healing + group_heal_out
                            end
                            --
                            applyTriggerSpells( )
                            --
                            
                             -- Healing Caps
                            healing = min( healing, Player.health_deficit )
                            healing = max( healing, 0 )
                            
                            local groupdeficit = 0
                            for t_it = 1, action_targets do
                                groupdeficit = groupdeficit + ( aura_env.healer_targets[ t_it ] and aura_env.healer_targets[ t_it ].deficit or 0 )
                            end
                            
                            group_healing = min( group_healing, groupdeficit )
                            group_healing = max( group_healing, 0 )
                            
                            -- Damage Caps
                            if action_targets == 1 and aura_env.targetHealthRemaining > 0 then
                                damage = min ( aura_env.targetHealthRemaining, damage )
                            end
                            
                            if aura_env.combatHealthRemaining > 0 then
                                damage = min ( aura_env.combatHealthRemaining, damage )
                            end
                            
                            -- -----------------------------------------------------
                            
                            -- Adjust damage / heal value based on option sliders
                            local adjusted = damage
                            
                            if spec == aura_env.SPEC_INDEX["MONK_BREWMASTER"]  then
                                adjusted = ( adjusted * brewmaster_dmg_ratio ) 
                                + ( ( healing + stagger_reduction + mitigation ) * brewmaster_heal_ratio )
                                
                                -- Exploding Keg         
                                if Player.findAura( 325153 ) then 
                                    adjusted = damage
                                end
                            elseif spec == aura_env.SPEC_INDEX["MONK_MISTWEAVER"]  then
                                -- TODO: Make this variable
                                local mistweaver_heal_ratio = 0.5
                                local mistweaver_dmg_ratio = 0.5
                                
                                adjusted = ( adjusted * mistweaver_dmg_ratio ) + ( ( healing + group_healing ) * mistweaver_heal_ratio )
                            end
                            
                            -- Generic Brew CDR
                            if spec == aura_env.SPEC_INDEX["MONK_BREWMASTER"] and action.brew_cdr then
                                local brew_cdr = action.brew_cdr or 0 
                                local brew_list = { "purifying_brew", "celestial_brew", "fortifying_brew", "black_ox_brew", "bonedust_brew" }
                                
                                if type( brew_cdr ) == "function" then
                                    brew_cdr = brew_cdr()
                                end
                                
                                if brew_cdr > 0 then
                                    -- initialize table
                                    action.reduces_cd = action.reduces_cd or {}
                                    
                                    for _, brew in pairs ( brew_list ) do
                                        if spells[brew] and spells[brew].spellID then
                                            -- 000 is a unique identifier for general brew cdr
                                            -- this allows usage of both brew_cdr and reduces_cd for brew spells
                                            action.reduces_cd[brew.."-000"] = brew_cdr
                                        end
                                    end
                                end
                            end
                            
                            -- CDR
                            if action.reduces_cd then
                                
                                local cdr_value = 0
                                local cdr_cost = 0
                                local cdr_time = 0
                                
                                for spell, value in pairs( action.reduces_cd ) do
                                    spell = gsub( spell, "%-.*", "" )
                                    local cdr = value  
                                    
                                    if type(cdr) == "function" then
                                        cdr = cdr()
                                    end
                                    
                                    local spell_action = spells[spell]
                                    if cdr > 0 and spell_action and spell_action.spellID then
                                        
                                        local timeLeft, cd = aura_env.getCooldown( spell_action.spellID )
                                        
                                        if cd > 0 and timeLeft > 0 then
                                            local total_cdr = min( cdr, timeLeft - execute_time )
                                            local mod_rate =  aura_env.actionModRate( spell_action )
                                            if mod_rate < 1 then
                                                total_cdr = total_cdr * ( 1 - mod_rate )
                                            end
                                            if total_cdr > 0 then
                                                local spell_raw = spellRaw( spell )
                                                local spell_time = spell_action.time_total or spell_action.base_execute_time
                                                if spell_raw > adjusted then
                                                    spell_raw = spell_raw - adjusted
                                                    cdr_value = cdr_value + ( total_cdr / cd * spell_raw )
                                                    cdr_cost  = cdr_cost + ( max( 0, ( spell_action.cost_total or 0 ) ) * total_cdr / cd )
                                                    cdr_time  = cdr_time + ( spell_time * total_cdr / cd )
                                                end
                                            end
                                        end        
                                    end
                                end
                                
                                adjusted     = adjusted + cdr_value
                                cost         = cost + cdr_cost
                                execute_time = execute_time + cdr_time
                            end
                            
                            -- Action has increased recharge rate
                            local actionModRate = aura_env.actionModRate( action )
                            
                            if action_cd_remains == 0 and action_cooldown > 0 and actionModRate < 1 then
                                local duration = action_cooldown
                                
                                -- TODO: How can I get modRate duration dynamically for unknown effects? 
                                if serenity and action.affected_by_serenity and serenity.remaining > action_delay then
                                    duration = min( duration, serenity.remaining )
                                end
                                
                                local recharge_cdr = min( duration, max( 0, action_cooldown - execute_time ) ) * ( 1 - actionModRate )
                                if recharge_cdr > 0 then
                                    local recast = 1 + ( recharge_cdr / action_cooldown )
                                    adjusted     = adjusted * recast
                                    cost         = cost * recast
                                    execute_time = execute_time * recast
                                end
                            end
                            
                            if spec == aura_env.SPEC_INDEX["MONK_WINDWALKER"] then
                                
                                -- Serenity / Chi Gains
                                if serenity and serenity.remaining > action_delay then
                                    cost = 0
                                else
                                    local chi_deficit = Player.chi_max - Player.chi
                                    
                                    if chi_deficit > 0 then
                                        
                                        local gain = action.chi_gain and action.chi_gain() or 0
                                        local energy_gain = 0
                                        
                                        if energy_cost > 0 and aura_env.fight_remains > 5 then
                                            
                                            local energy_deficit = Player.energy_max - Player.energy
                                            
                                            local net_energy = energy_cost - ( Player.eps * execute_time )
                                            net_energy = min( energy_deficit, net_energy )
                                            net_energy = max( 0 - Player.energy, net_energy)
                                            
                                            local tp_gained = net_energy / aura_env.energy_base_cost( spells["tiger_palm"].spellID )
                                            
                                            energy_gain = 2 * tp_gained
                                        end
                                        
                                        -- Ability will overcap Chi
                                        if ( chi_deficit - gain < 0 ) then
                                            gain = ( gain * -1 ) + ( chi_deficit - energy_gain )
                                            energy_gain = 0
                                        end
                                        
                                        cost = cost - ( gain + energy_gain )
                                    end
                                end
                                
                                -- FoF Canceling Logic
                                local fof_action = spells["fists_of_fury"]
                                
                                if Player.channel_id 
                                and fof_action
                                and Player.channel_id == fof_action.spellID then
                                    local remaining = ( Player.channel_end / 1000 ) - frameTime - Player.gcd_remains - action_delay
                                    local length = ( Player.channel_end - Player.channel_start ) / 1000
                                    if remaining > 0 then 
                                        local tick_time = length / 4
                                        local ticks_remaining = 1 + floor( remaining / tick_time )
                                        
                                        if Player.gcd_remains == 0 then
                                            aura_env.tick_update = frameTime + ( remaining % tick_time )
                                        end
                                        
                                        local fof_tick_raw = ( aura_env.snapshot_fof or 0 ) / fof_action.ticks
                                        * global_modifier( fof_action ) * targetAuraEffect( fof_action )
                                        local fof_total = ( fof_tick_raw * ticks_remaining ) * ( 1 + aura_env.error_margin )
                                        
                                        if not action.background and not action.copied_by_sef then
                                            if Player.findAura( 137639 ) then -- Storm, Earth, and Fire
                                                local sef_ticks = 1 + floor( min( remaining, 1 ) / tick_time )
                                                local sef_gain = fof_tick_raw * 0.84 * sef_ticks * ( 1 + aura_env.error_margin )
                                                adjusted = adjusted + sef_gain
                                            end
                                        end
                                        
                                        action_set( {
                                                type         = "damage",
                                                name         = "fof_remaining",
                                                raw          = fof_total,
                                                execute_time = remaining,
                                                cb           = fof_action,
                                        })
                                    end
                                else
                                    if name == "fists_of_fury" then
                                        aura_env.snapshot_fof = adjusted / temporary_amplifiers
                                    end
                                end
                            end
                            
                            action.cost_total = cost
                            action.time_total = execute_time
                            
                            action_set( { 
                                    type = action_type,
                                    name = name,
                                    raw = adjusted,
                                    cost = cost,
                                    damage = damage,
                                    healing = healing,
                                    group_healing = group_healing,
                                    cooldown = action_cooldown,
                                    cooldown_remains = action_cd_remains,
                                    starts_cooldown = start_cooldown,
                                    delay = action_delay,
                                    chi_cost = aura_env.chi_base_cost( spellID ),
                                    energy_cost = aura_env.energy_base_cost( spellID ),
                                    mana_cost = aura_env.mana_base_cost( spellID ),
                                    execute_time = execute_time,
                                    background = action.background,
                                    t_amp = temporary_amplifiers,
                                    mastery_break = mastery_break,
                                    combo_base = combo_base,
                            })
                        end
                    end
                end -- continue
            end
            aura_env.spell_range_min = aura_env.spell_range_min + process_trees
            
            local action_cpu_time = debugprofilestop()
            local actions_current = debug_process_max - debug_process_min
            local action_cpu_avg  = action_cpu_time / actions_current
            
            if aura_env.action_cpu_average then
                aura_env.action_cpu_average = ( aura_env.action_cpu_average + action_cpu_avg ) / 2
            else
                aura_env.action_cpu_average = action_cpu_avg
            end
            
            if action_cpu_time > 0 and profiler_enabled then
                aura_env.profiler_out[ "Update ActionList" ] = action_cpu_time 
            end
        end
        
        if fullUpdate and next( actionlist ) ~= nil then
            
            -- Sort and rank candidate actions
            -- -----------------------------------------------------------
            local t = min( 5, aura_env.fight_remains )
            local a = Player.action_modifier
            local c = ( spec == aura_env.SPEC_INDEX["MONK_WINDWALKER"]  and Player.chi ) 
            or ( spec == aura_env.SPEC_INDEX["MONK_MISTWEAVER"]  and Player.mana / Player.eps ) 
            or Player.energy / Player.eps
            local o = 0
            local s = 0
            local n = #actionlist
            local ow = {}
            
            if n > 0 then
                
                debugprofilestart()
                
                local hashed = {}
                local potential_d = 0
                local potential_h = 0
                
                local function sortActionList( list )
                    local maximum_sequence = 5
                    local minimum_step = 1
                    local sequence_n = 0
                    local sequence_t = {}
                    local previous_s = s
                    local non_op = false
                    local pool = false
                    
                    o = global_modifier( default_action, t, false ) * targetAuraEffect( default_action, t ) 
                    if o > a then
                        pool = true
                    else
                        if o < a then
                            local bi_t = t / 2 
                            local bi_o = global_modifier( default_action, bi_t, false ) * targetAuraEffect( default_action, bi_t )
                            if bi_o < a then
                                t = bi_t
                            end
                        end
                    end
                    
                    if not pool then
                        -- Sort actions by time
                        sort( list, function( l, r )
                                return l.d_time > r.d_time
                        end)
                        
                        local validActions = {}
                        for i = 1, n do
                            local action = list[ i ]
                            if not action or not action.cb or not action.cb.spellID 
                            or action.background or action.raw <= 0
                            or not IsSpellKnown( action.cb.replaces or action.cb.spellID ) then
                                list[ i ]         = nil
                                validActions[ i ] = nil
                            else                            
                                validActions[ i ] = action
                                hashed[ i ]       = list[ i ]
                            end
                        end
                        
                        while true do
                            
                            local delta_s = s - previous_s
                            if non_op or s >= t or c <= 0 or delta_s < minimum_step then
                                break
                            end
                            
                            previous_s = s
                            
                            local n_actions = #validActions
                            if n_actions <= 1 then
                                return list
                            end
                            
                            non_op = true
                            
                            for j, action in pairs( validActions ) do
                                
                                local cd_remaining = ( ow[ action.name ] or action.cd_remains ) - s
                                
                                if action.cost <= c and cd_remaining <= 0 and action.delay <= ( t - s ) then
                                    
                                    non_op = false
                                    
                                    sequence_n = sequence_n + 1
                                    sequence_t[ #sequence_t + 1 ] = action.name
                                    
                                    s = s + action.execute_time
                                    c = c - action.cost
                                    
                                    if s >= t or action.execute_time == 0 or action.cost <= 0 or sequence_n >= maximum_sequence then
                                        Player.action_sequence = sequence_t
                                        return list
                                    end
                                    
                                    if c <= 0 then
                                        break
                                    end
                                    
                                    ow[ action.name ] = action.cooldown
                                    for _, v in pairs( action.start_cd ) do
                                        local trigger = hashed[ actionhash[ v ] ]
                                        if trigger then
                                            ow[ trigger.name ] = trigger.cooldown
                                        end
                                    end
                                elseif cd_remaining > t or action.delay > t then
                                    validActions[ j ] = nil
                                end
                            end
                        end
                    end
                    -- Adjust by cost 
                    sort( list, function( l, r )
                            return l.d_cost > r.d_cost
                    end )
                    local _, start = next( list )
                    Player.action_sequence = next( sequence_t ) ~= nil and sequence_t or { start.name }
                    return list
                end
                
                actionlist = sortActionList( actionlist )
                
                local debug_out = {}
                local action_debug = false
                
                for k, v in pairs( actionlist ) do
                    if not v.raw or v.raw == 0 then
                        jeremy.rank[ v.name ] = 0
                    elseif ( spec == aura_env.SPEC_INDEX["MONK_WINDWALKER"] and v.chi_cost > Player.chi )
                    or ( spec == aura_env.SPEC_INDEX["MONK_MISTWEAVER"]  and v.mana_cost > Player.mana )
                    or ( spec == aura_env.SPEC_INDEX["MONK_BREWMASTER"]  and v.energy_cost > Player.energy ) then
                        jeremy.rank[ v.name ] = 0
                    elseif v.mastery_break
                    and aura_env.fight_remains > 1
                    and v.name ~= "touch_of_death" 
                    and ( v.name ~= "spinning_crane_kick" or Player.bdb_targets == 0 ) then
                        jeremy.rank[ v.name ] = 0                         
                    else
                        local action_name = v.combo_base and v.combo_base or v.name
                        jeremy.rank [ action_name ] = jeremy.rank [ action_name ] or k
                        if action_debug and k <= 5 then
                            debug_out[ k ] = {
                                name = v.name,
                                dpet = v.d_time,
                                raw = v.raw,
                                cost = v.cost,
                                execute_time = v.execute_time,
                                delay = v.delay,
                            }
                        end
                    end
                end
                if next( debug_out ) ~= nil then
                    ScanEvents( "JEREMY_DEBUG_PRIORITY", debug_out )
                end
                
                -- FoF Initial execute action
                -- after cast it will be handled by fof_remaining
                if jeremy.rank["fist_of_fury"] and jeremy.rank["fists_of_fury_cancel"] then
                    if jeremy.rank["fists_of_fury_cancel"] < jeremy.rank["fists_of_fury"] and jeremy.rank["fists_of_fury_cancel"] > 0 then
                        jeremy.rank["fists_of_fury"] = jeremy.rank["fists_of_fury_cancel"]
                    end
                end
                
                local rank_cpu_time = debugprofilestop()
                local actions_current = n
                local rank_cpu_avg  = rank_cpu_time / actions_current
                
                if aura_env.rank_cpu_average then
                    aura_env.rank_cpu_average = ( aura_env.rank_cpu_average + rank_cpu_avg ) / 2
                else
                    aura_env.rank_cpu_average = rank_cpu_avg
                end
                
                if rank_cpu_time > 0 and profiler_enabled then
                    aura_env.profiler_out[ "Rank Candidate Actions" ] = rank_cpu_time
                end   
                
            end
            -- -----------------------------------------------------------
            
            -- Ability options
            jeremy.boss_lockdown = aura_env.boss_lockdown
            jeremy.fight_remains = aura_env.fight_remains
            jeremy.target_ttd = aura_env.target_ttd
            
            if aura_env.target_count > 1 and targets_tod_range == 1 and aura_env.target_ttd <= 1 then
                jeremy.force_tod = true
            else
                jeremy.force_tod = false
            end
            
            local woo_buff = ( spec == aura_env.SPEC_INDEX[ "MONK_BREWMASTER" ] and Player.findAura( 387184 ) ) or nil
            if woo_buff and woo_buff.remaining <= ( 0.25 + Player.gcd_duration ) * ( 4 - aura_env.woo_best ) then
                jeremy.woo_prio = true
            else
                jeremy.woo_prio = false
            end
            
            -- Bountiful Brew holding
            if aura_env.bdb_dur_total == 0 or aura_env.config.hide_bdb < 2 then
                jeremy.hold_bdb = false
            else
                local avgDuration = aura_env.bdb_dur_total / Player.bdb_targets
                local recast = ( aura_env.target_count - Player.bdb_targets ) * 10
                recast = recast + ( Player.bdb_targets * ( min( 20, avgDuration + 10 ) ) )
                local opportunity = aura_env.bdb_dur_total + recast - ( avgDuration / 54 * recast ) 
                if Player.bdb_targets > 0 and ( recast / opportunity ) < 0.9 then
                    jeremy.hold_bdb = true
                else
                    jeremy.hold_bdb = false
                end
            end
            
            -- end of ability options
            -- -------------------------------------------------------------
            
            -- Passed Configuration Options
            jeremy.options = {}        
            jeremy.options.limit = aura_env.config.limit or 5
            jeremy.options.inverse = ( aura_env.config.inverse == 2 ) or false
            jeremy.options.hold_sef = aura_env.config.hold_sef or 1
            
            aura_env.jeremy_update = jeremy
            ScanEvents( "JEREMY_UPDATE", jeremy )
            
            return true
            
        end
        
        return false
    end
    
    if event == "ENCOUNTER_START" then
        aura_env.encounter_id = tostring( ... )
        return false
    elseif event == "ENCOUNTER_END" then
        aura_env.encounter_id = nil
        return false
    end
    
    if event == "JEREMY_STARTBAR" or event == "RELOE_SPELLCD_STATE_UPDATE" then
        
        local key, time, spell, srcGUID
        
        if event == "RELOE_SPELLCD_STATE_UPDATE" then
            spell, srcGUID, key, time = ...
            if not ( spell and time ) then
                return
            end
        else
            key  = select( 3, ... )
            time = select( 5, ... )
        end
        
        key = tostring( key )
        
        if key and time then
            
            local config = aura_env.bw_config[ key ] 
            
            if config and config.enabled then
                local expirationTime = frameTime + time
                local config_type = config.type or "ERROR"
                
                local t_key = (srcGUID or "SB").."-"..key
                
                if config_type == "ADD_SPAWN" then
                    aura_env.BW_add_timers[ t_key ] = {
                        key = key,
                        expire = expirationTime,
                        count = config.count or 0,
                        encounterId = aura_env.encounter_id or -1,
                        srcGUID = srcGUID,
                        type = config_type,
                    }
                elseif config_type == "INTERMISSION" then
                    aura_env.BW_intermission_timers[ t_key ] =  {
                        key = key,
                        expire = expirationTime,
                        unitid = config.unitid or "boss1",
                        encounterId = aura_env.encounter_id or -1,
                        srcGUID = srcGUID,                        
                        type = config_type,
                    }           
                elseif config_type == "TANKBUSTER" then
                    
                    local affects = config.affects or 1
                    if affects == 1 and spec == aura_env.SPEC_INDEX["MONK_BREWMASTER"]
                    or affects == 2 and spec ~= aura_env.SPEC_INDEX["MONK_BREWMASTER"]
                    or affects == 3 then
                        -- Send message to Raid Ability Timeline
                        if event == "RELOE_SPELLCD_STATE_UPDATE" then
                            local Enemy = aura_env.GetEnemy( srcGUID )
                            ScanEvents( "JEREMY_TIMELINE_UPDATE", spell, srcGUID, key, time, Enemy.marker )
                        end
                        
                        aura_env.BW_buster_timers [ t_key ] = {
                            key = key,
                            expire = expirationTime,
                            damage_type = config.damage_type or 1,
                            encounterId = aura_env.encounter_id or -1,
                            srcGUID = srcGUID,
                            type = config_type,
                        }
                    end
                end
            end
        end
        
        return false
    end
    
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local  _, _, spellID = ...
        
        if spellID == 137639 then
            aura_env.sef_fixate = nil
        elseif spellID == 221771 then
            local dstGUID = UnitGUID( "target" )
            
            aura_env.sef_fixate = dstGUID
            aura_env.last_fixate_bonus = aura_env.forwardModifier( aura_env.spells["tiger_palm"], 1 )
        end
        
        if spellID and aura_env.combo_strike[spellID] then
            if Player.last_combo_strike ~= spellID then
                Player.last_combo_strike = spellID
                aura_env.fast = true
            end          
        end
        
        return false
    end
    
    if event == "COMBAT_RATING_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        aura_env.initGear()
    end
    
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        aura_env.initSpecialization()
    end
    
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        aura_env.updateDB()
        
        Combat = {
            avg_level = 0,
            damage_by_level = 0,
            damage_taken = 0,
            damage_taken_avoidable = 0,
            damage_taken_unavoidable = 0,
            recent_damage = {},
        }
        
        aura_env.CURRENT_MARKERS = {}
    end
    
    if event == "UNIT_POWER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        
        Player.eps        = GetPowerRegen()
        Player.mana       = UnitPower( "player" , 0 )
        Player.energy     = UnitPower( "player" , 3 )
        Player.energy_max = UnitPowerMax( "player", 3 )
        Player.chi        = UnitPower( "player" , 12 )
        Player.chi_max    = UnitPowerMax( "player", 12 )
        
        
        local gcd_start = GetSpellCooldown( 61304 )
        
        if gcd_start > 0 then
            Player.gcd_duration = gcdDuration()
            Player.gcd_remains = Player.gcd_duration - ( frameTime - gcd_start )    
        else
            Player.gcd_duration = 0
            Player.gcd_remains = 0
        end
        
        if Player.eps > 0 then
            Player.mana       = Player.mana + ( Player.eps * Player.gcd_remains )
            Player.energy     = Player.energy + ( Player.eps * Player.gcd_remains )
            Player.energy_ttm = ( Player.energy_max - Player.energy ) / Player.eps     
        end
        
        return true
    end
    
    -- Everything below returns false
    -- ------------------------------
    
    if event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        local unitID = ...
        local unitGUID = UnitGUID( unitID )
        
        if aura_env.validTarget( unitID ) then
            
            local Enemy = aura_env.GetEnemy( unitGUID )
            
            Enemy.healthActual  = UnitHealth( unitID ) 
            - ( ( aura_env.earlyDeath[ Enemy.npcid ] or 0 ) * UnitHealthMax( unitID ) ) 
            + UnitGetTotalAbsorbs( unitID )
            
            Enemy.healthPct     = min( 1, Enemy.healthActual / UnitHealthMax( unitID ) )
            
            if Enemy.lastHealth and Enemy.lastSeen then
                
                local difference = Enemy.lastHealth - Enemy.healthPct
                
                if difference > 0 then
                    local elapsed = frameTime - Enemy.lastSeen
                    
                    if not Enemy.n or Enemy.n == 0 then
                        Enemy.rate = difference / elapsed
                        Enemy.n = 1
                    else
                        local samples = min( Enemy.n, 9 )
                        local newRate = Enemy.rate * samples + ( difference / elapsed )
                        Enemy.n = samples + 1
                        Enemy.rate = newRate / Enemy.n
                    end
                end
            end
            
            Enemy.lastHealth = Enemy.healthPct
            Enemy.lastSeen = frameTime 
            
            if Enemy.rate then
                
                Enemy.ttd = Enemy.healthPct / Enemy.rate
                
                if Enemy.intermission then
                    Enemy.ttd = min( Enemy.ttd, Enemy.intermission )    
                end
                
                if unitGUID == UnitGUID( "target" ) then
                    aura_env.target_ttd = max( 1, floor( Enemy.ttd + 0.5 ) )
                    aura_env.taret_abs = UnitGetTotalAbsorbs( unitID ) or 0
                end
            end
        end
        
        return false
    end
    
    if event == "NAME_PLATE_UNIT_ADDED"  or event == "NAME_PLATE_UNIT_UPDATED" or event == "UPDATE_MOUSEOVER_UNIT" then
        
        local unitID, unitGUID
        
        if event == "UPDATE_MOUSEOVER_UNIT" then
            
            -- Only use this event if there is no nameplate available
            -- and there is a valid mouseover
            unitID   = "mouseover"    
            unitGUID = UnitGUID( "mouseover" )
            
            if GetNamePlateForUnit( "mouseover" ) then
                return
            end
        else
            unitID = ...
            unitGUID = ( unitID and UnitGUID( unitID ) ) or nil
        end
        
        if not unitGUID then
            return
        end
        
        if UnitExists( unitID ) then
            
            local Enemy = aura_env.GetEnemy( unitGUID )
            
            if not Enemy.isBoss then
                if unitGUID == UnitGUID( "boss1" ) 
                or unitGUID == UnitGUID( "boss2" )
                or unitGUID == UnitGUID( "boss3" ) 
                or unitGUID == UnitGUID( "boss4" ) 
                or unitGUID == UnitGUID( "boss5" ) then
                    Enemy.isBoss = true
                end
            end
            
            local oldMarker = Enemy.marker
            
            Enemy.marker    = GetRaidTargetIndex( unitID )
            Enemy.level     = UnitLevel( unitID )
            
            Enemy.priority_modifier = aura_env.npc_priority[ Enemy.npcid ] or 1.0
            
            local am_level = aura_env.config.automarker_enable 
            local am_enable = 
            am_level > 1 
            or ( am_level == 3 and UnitGroupRolesAssigned( "player" ) == "TANK" ) 
            or ( am_level == 4 and UnitIsGroupLeader( "player" ) )
            
            if aura_env.AUTOMARKER and am_enable then
                local value = aura_env.AUTOMARKER[ UnitName( unitID ) ] or aura_env.AUTOMARKER[ Enemy.npcid ]
                
                if value then
                    local mark = find( value, "MARK" ) ~= nil
                    Enemy.interruptTarget = find( value, "INTERRUPT" ) ~= nil
                    Enemy.stunTarget = find( value, "STUN" ) ~= nil
                    
                    local l, h = 1, 6
                    if find( value, "KILL" ) then
                        l, h = 7, 8
                    end
                    
                    if Enemy.marker then
                        aura_env.CURRENT_MARKERS[ Enemy.marker ] = unitGUID
                    elseif mark == true then
                        
                        local marks_available = false
                        
                        for m = h, l, -1 do
                            if aura_env.CURRENT_MARKERS[ m ] == nil then
                                marks_available = true
                                break
                            end
                        end
                        
                        for m = h, l, -1 do
                            
                            -- We need a mark, can we steal one?
                            if not marks_available and aura_env.CURRENT_MARKERS[ m ] then
                                local marked_enemy = aura_env.GetEnemy( aura_env.CURRENT_MARKERS[ m ]  )
                                -- Do not steal from enemy in combat
                                if not marked_enemy.inCombat then
                                    if Enemy.inCombat
                                    or Enemy.range < marked_enemy.range then
                                        aura_env.CURRENT_MARKERS[ m ] = nil
                                    end
                                end
                            end
                            
                            if aura_env.CURRENT_MARKERS[ m ] == nil
                            then
                                SetRaidTarget( unitID, m )
                                aura_env.CURRENT_MARKERS[ m ] = unitGUID
                                Enemy.marker = m
                                break
                            end
                        end
                    end
                end
            end
            
            if Enemy.marker ~= oldMarker then
                ScanEvents( "JEREMY_MARKER_CHANGED", unitGUID, Enemy.marker )
            end
        end
        
        return false
    end
    
    if event == "UNIT_AURA" or event == "UNIT_AURA_FULL_UPDATE" then
        local unitID, updateInfo = ...
        local unitGUID = UnitGUID( unitID )
        
        if unitID == "player" or aura_env.validTarget( unitID ) then
            
            local Unit = ( unitID == "player" and Player ) or aura_env.GetEnemy( unitGUID )
            
            local parseAuraData = function( auraData )
                auraData.name = gsub( lower( auraData.name ), "%s+", "_" )
                auraData.stacks = auraData.applications or 0
                return auraData
            end
            
            if event == "UNIT_AURA_FULL_UPDATE" then
                if not Unit.lastFullUpdate or Unit.lastFullUpdate < frameTime - aura_env.update_rate then
                    Unit.auraExclusions = {}
                    Unit.auraDataByInstance = {}
                    Unit.auraInstancesByID = {}
                    
                    -- Monk Diffuse Magic
                    if Unit == Player then
                        Unit.diffuse_auras = {}
                        Unit.diffuse_reflects = {}
                    end
                    
                    local auraSlots = { UnitAuraSlots( unitID, "HELPFUL|HARMFUL" ) }
                    for slot in pairs( auraSlots ) do
                        local auraData = GetAuraDataBySlot( unitID, slot )
                        if auraData then
                            
                            local instanceID = auraData.auraInstanceID
                            local spellId = auraData.spellId
                            
                            if aura_env.auraExclusions[ spellId ] then
                                Unit.auraExclusions[ instanceID  ] = spellId
                            end
                            
                            -- Monk Diffuse Magic
                            if Unit == Player then
                                local valid_diffuse = aura_env.diffuse_options[ spellId ]
                                if valid_diffuse and valid_diffuse.enabled then
                                    Unit.diffuse_auras[ instanceID  ] = true
                                    if valid_diffuse.reflect then
                                        Unit.diffuse_reflects[ instanceID  ] = true
                                    end
                                end
                            end
                            
                            Unit.auraInstancesByID[ spellId ] = Unit.auraInstancesByID[ spellId ] or {}
                            Unit.auraInstancesByID[ spellId ][ instanceID ] = true 
                            Unit.auraDataByInstance[ instanceID  ] = parseAuraData( auraData )
                        end
                    end
                    Unit.needsFullUpdate = false
                    Unit.lastFullUpdate = frameTime
                end
            else    
                if updateInfo.isFullUpdate then
                    Unit.needsFullUpdate = true
                else
                    if updateInfo.addedAuras then
                        for _, auraData in pairs( updateInfo.addedAuras ) do
                            
                            local instanceID = auraData.auraInstanceID
                            local spellId = auraData.spellId   
                            
                            if aura_env.auraExclusions[ spellId ] then 
                                Unit.auraExclusions[ instanceID ] = spellId
                            end
                            
                            -- Monk Diffuse Magic
                            if Unit == Player then
                                local valid_diffuse = aura_env.diffuse_options[ spellId ]
                                if valid_diffuse and valid_diffuse.enabled then
                                    Unit.diffuse_auras[ instanceID ] = true
                                    if valid_diffuse.reflect then
                                        Unit.diffuse_reflects[ instanceID ] = true
                                    end
                                end
                            end                            
                            
                            Unit.auraInstancesByID[ spellId ] = Unit.auraInstancesByID[ spellId ] or {}
                            Unit.auraInstancesByID[ spellId ][ instanceID ] = true 
                            Unit.auraDataByInstance[ instanceID ] = parseAuraData( auraData )
                        end
                    end
                    
                    if updateInfo.updatedAuraInstanceIDs then
                        for _, instanceID in pairs( updateInfo.updatedAuraInstanceIDs ) do
                            local auraData = GetAuraDataByAuraInstanceID( unitID, instanceID )
                            if auraData then
                                
                                auraData.name = gsub( lower( auraData.name ), "%s+", "_" )
                                auraData.stacks = auraData.applications or 0
                                
                                local spellId = auraData.spellId   
                                
                                Unit.auraInstancesByID[ spellId ] = Unit.auraInstancesByID[ spellId ] or {}
                                Unit.auraInstancesByID[ spellId ][ instanceID ] = true 
                                Unit.auraDataByInstance[ instanceID ] = parseAuraData( auraData )  
                            end
                        end
                    end
                    
                    if updateInfo.removedAuraInstanceIDs then
                        for _, instanceID in pairs( updateInfo.removedAuraInstanceIDs ) do
                            
                            Unit.auraExclusions[ instanceID ] = nil
                            
                            -- Monk Diffuse Magic
                            if Unit == Player then
                                Unit.diffuse_auras[ instanceID ] = nil
                                Unit.diffuse_reflects[ instanceID ] = nil
                            end       
                            
                            if Unit.auraDataByInstance[ instanceID ] then
                                local spellId = Unit.auraDataByInstance[ instanceID ].spellId
                                Unit.auraInstancesByID[ spellId ][ instanceID ] = nil
                                Unit.auraDataByInstance[ instanceID ] = nil
                            end
                        end
                    end 
                end
            end
        end
        
        return false
    end
    
    if event == "UNIT_THREAT_LIST_UPDATE" or event == "NAME_PLATE_UNIT_REMOVED" then
        local unitID = ...
        local unitGUID = UnitGUID( unitID )
        
        if not unitGUID then
            return
        end
        
        if not UnitExists( unitID ) then
            aura_env.ResetEnemy( unitGUID )
        else
            local Enemy = aura_env.GetEnemy( unitGUID )
            
            if UnitAffectingCombat( unitID ) then
                Enemy.inCombat = true
            elseif Enemy.inCombat then
                local unitInCombat = false
                for it in WA_IterateGroupMembers() do
                    if UnitThreatSituation( it, unitID ) then
                        unitInCombat = true
                        break
                    end
                end
                
                if not unitInCombat then
                    aura_env.ResetEnemy( unitGUID )
                end
            end
            
            if Enemy.inCombat and not Enemy.combatStart then
                Enemy.combatStart = frameTime
            end
        end
        
        ScanEvents( "NAME_PLATE_UNIT_UPDATED", unitID )
        
        return false
    end
    
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        
        local LogDamage = function (_, eventtype, _, srcGUID, srcName, srcFlags, _, dstGUID, ...)
            
            if eventtype == nil 
            or eventtype == "ENVIRONMENTAL_DAMAGE" 
            or not find( eventtype, "_DAMAGE" ) then
                return false
            end
            
            local enemyGUID = nil
            
            if dstGUID == UnitGUID( "player" ) then
                enemyGUID = srcGUID
            else
                local mask = COMBATLOG_OBJECT_AFFILIATION_MASK
                local bitfield = bit_band( srcFlags, mask )
                
                if srcGUID == UnitGUID( "player" )
                or srcGUID == UnitGUID( "pet" )
                or bitfield == COMBATLOG_OBJECT_AFFILIATION_MINE then
                    enemyGUID = dstGUID
                end
            end
            
            if enemyGUID == nil then
                return false
            end
            
            local Enemy = aura_env.GetEnemy( enemyGUID )
            
            local spellID, spellSchool, amount
            
            if eventtype == "SWING_DAMAGE" then
                _, _, _, amount = ...
            else
                _, _, _, spellID, _, spellSchool, amount = ...
            end
            
            spellSchool = spellSchool or 1
            spellID = spellID or 0
            
            if amount == nil
            or type( amount ) ~= "number"
            or amount == 0 then
                return false
            end
            
            if srcGUID == enemyGUID then
                if dstGUID == UnitGUID( "player" ) and Enemy.level > 0 then
                    
                    Combat.damage_by_level = Combat.damage_by_level + ( Enemy.level * amount )
                    Combat.damage_taken = Combat.damage_taken + amount
                    Combat.avg_level = Combat.damage_by_level / Combat.damage_taken;
                    
                    Combat.recent_damage[ #Combat.recent_damage + 1 ] = {
                        amount = amount,
                        expire = frameTime + aura_env.RECENT_DURATION
                    }
                    
                    if spellSchool == 1 and not find( eventtype, "PERIODIC" ) then
                        Combat.damage_taken_avoidable = Combat.damage_taken_avoidable + amount
                    else
                        Combat.damage_taken_unavoidable = Combat.damage_taken_unavoidable + amount
                    end              
                end
            else
                -- Not pet damage
                if srcGUID == UnitGUID( "player" ) then
                    -- spell tracking ... 
                    if spellID and aura_env.pull_hash ~= "" then
                        aura_env.coneTickListener( spellID, enemyGUID )
                    end
                end
            end
        end
        
        local LogDeath = function (_, eventtype, _, srcGUID, _, _, _, dstGUID, ...)
            if eventtype == "UNIT_DIED" or eventtype == "UNIT_DESTROYED" or eventtype == "UNIT_DISSIPATES" then
                aura_env.ResetEnemy( dstGUID, true )
            end
        end
        
        if InCombatLockdown() then
            local params = CombatLogGetCurrentEventInfo()
            LogDamage( params )
            LogDeath( params )
        end
        
        return false
        
    end   
    
    return false
end

