-- Waterside spots for drowning calls: points on the shoreline of the sea, the Alamo Sea,
-- rivers and lakes, taken from the map. The scene NPC is moved to the nearest dry spot
-- next to water, so a point does not have to be exact. z is approximate.
-- Used for drowning AI calls unless Config.AiCalls.typeLocations.drowning is set.

Config.Waterside = {
    -- Beaches (Pacific coast, Paleto Bay, Del Perro, Vespucci)
    vector3(104.9, 7257.3, 2.0), vector3(351.9, 7008.5, 2.0), vector3(18.5, 6899.3, 2.0),
    vector3(592.6, 6753.6, 2.0), vector3(932.1, 6668.7, 2.0), vector3(-222.2, 6644.4, 2.0),
    vector3(1370.4, 6644.4, 2.0), vector3(-493.8, 6426.0, 2.0), vector3(-963.0, 6280.3, 2.0),
    vector3(-654.3, 6116.5, 2.0), vector3(-845.7, 5825.2, 2.0), vector3(-1030.9, 5521.8, 2.0),
    vector3(-1395.1, 5461.2, 2.0), vector3(-1574.1, 5163.8, 2.0), vector3(-1771.6, 4878.6, 2.0),
    vector3(-2179.0, 4629.9, 2.0), vector3(-2401.2, 4356.8, 2.0), vector3(-2506.2, 4023.1, 2.0),
    vector3(-2574.1, 3683.3, 2.0), vector3(-2919.8, 3586.2, 2.0), vector3(-3154.3, 3325.2, 2.0),
    vector3(-2876.5, 3082.5, 2.0), vector3(-2648.1, 2809.5, 2.0), vector3(-3203.7, 1395.6, 2.0),
    vector3(-3296.3, 1061.9, 2.0), vector3(-3179.0, 734.2, 2.0), vector3(-3129.6, 388.3, 2.0),
    vector3(-3080.2, 42.5, 2.0), vector3(-2753.1, -91.0, 2.0), vector3(-2463.0, -285.2, 2.0),
    vector3(-2154.3, -455.1, 2.0), vector3(-1938.3, -728.2, 2.0), vector3(-1734.6, -1013.3, 2.0),
    vector3(-1500.0, -1274.3, 2.0), vector3(-1370.4, -1595.9, 2.0), vector3(-975.3, -1656.6, 2.0),
    vector3(-1228.4, -1911.4, 2.0),
    -- Rocky coast (east and north, fewer beaches)
    vector3(2290.1, 6759.7, 2.0), vector3(1555.6, 6644.4, 2.0), vector3(2925.9, 6468.4, 2.0),
    vector3(3549.4, 6152.9, 2.0), vector3(3574.1, 5461.2, 2.0), vector3(3672.8, 4775.5, 2.0),
    vector3(4037.0, 4186.9, 2.0), vector3(4024.7, 3416.3, 2.0), vector3(-2666.7, 2833.7, 2.0),
    vector3(3666.7, 2821.6, 2.0), vector3(-3043.2, 2208.7, 2.0), vector3(3191.4, 2172.3, 2.0),
    vector3(-3049.4, 1517.0, 2.0), vector3(3012.3, 1504.9, 2.0), vector3(3092.6, 819.2, 2.0),
    vector3(2876.5, 91.0, 2.0), vector3(2932.1, -600.7, 2.0), vector3(2635.8, -1225.7, 2.0),
    vector3(2740.7, -2008.5, 2.0), vector3(2179.0, -2457.5, 2.0), vector3(895.1, -2615.3, 2.0),
    -- Alamo Sea shore
    vector3(2259.3, 4666.3, 31.0), vector3(1925.9, 4587.4, 31.0), vector3(2500.0, 4490.3, 31.0),
    vector3(80.2, 4423.5, 31.0), vector3(1666.7, 4423.5, 31.0), vector3(944.4, 4417.5, 31.0),
    vector3(469.1, 4338.6, 31.0), vector3(1314.8, 4338.6, 31.0), vector3(-111.1, 4193.0, 31.0),
    vector3(734.6, 4193.0, 31.0), vector3(2475.3, 4193.0, 31.0), vector3(1888.9, 3998.8, 31.0),
    vector3(1543.2, 3932.0, 31.0), vector3(2339.5, 3926.0, 31.0), vector3(-123.5, 3895.6, 31.0),
    vector3(166.7, 3804.6, 31.0), vector3(956.8, 3713.6, 31.0), vector3(1358.0, 3689.3, 31.0),
    vector3(425.9, 3646.8, 31.0), vector3(191.4, 3452.7, 31.0),
    -- Zancudo River and the Raton Canyon river
    vector3(-1808.6, 4678.4, 11.7), vector3(-1586.4, 4478.2, 14.0), vector3(-419.8, 4478.2, 26.5),
    vector3(-851.9, 4423.5, 21.9), vector3(-1209.9, 4417.5, 18.1), vector3(-154.3, 4338.6, 29.4),
    vector3(185.2, 3379.9, 31.0), vector3(-86.4, 3131.1, 30.1), vector3(-561.7, 3003.6, 25.0),
    vector3(-993.8, 2858.0, 20.4), vector3(-2284.0, 2712.4, 6.6), vector3(-1246.9, 2694.2, 17.7),
    vector3(-1611.1, 2676.0, 13.8), vector3(-2586.4, 2663.8, 3.4), vector3(-1993.8, 2627.4, 9.7),
    -- Vinewood Lake (Vinewood Hills)
    vector3(-92.6, 995.1, 170.0), vector3(111.1, 989.1, 170.0), vector3(284.0, 885.9, 170.0),
    vector3(-259.3, 873.8, 170.0), vector3(-74.1, 788.8, 170.0), vector3(142.0, 746.4, 170.0),
    -- Land Act Reservoir (Tataviam)
    vector3(2061.7, 564.3, 120.0), vector3(1697.5, 418.7, 120.0), vector3(2463.0, 418.7, 120.0),
    vector3(2191.4, 339.8, 120.0), vector3(1944.4, 248.8, 120.0), vector3(1746.9, 60.7, 120.0),
    vector3(2098.8, 42.5, 120.0),
    -- Mirror Park lake
    vector3(1043.2, -309.5, 56.0), vector3(913.6, -388.3, 56.0), vector3(1160.5, -534.0, 56.0),
    vector3(1098.8, -649.3, 56.0), vector3(1228.4, -679.6, 56.0),
    -- Vespucci Canals
    vector3(-956.8, -898.1, 2.0), vector3(-1166.7, -964.8, 2.0), vector3(-864.2, -1031.6, 2.0),
    vector3(-1067.9, -1092.2, 2.0),
}
