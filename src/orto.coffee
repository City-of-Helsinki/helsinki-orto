map = L.map('map').setView([60.171944, 24.941389], 15)
osm_layer = L.tileLayer('http://{s}.tile.cloudmade.com/BC9A493B41014CAABB98F0471D759707/997/256/{z}/{x}/{y}.png',
    maxZoom: 18,
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="http://cloudmade.com">CloudMade</a>'
)

orto1943_layer = L.tileLayer.wms WMS_SERVER_URL,
    layers: 'hel:orto1943'
orto1964_layer = L.tileLayer.wms WMS_SERVER_URL,
    layers: 'hel:orto1964'
orto1976_layer = L.tileLayer.wms WMS_SERVER_URL,
    layers: 'hel:orto1976'
orto1988_layer = L.tileLayer.wms WMS_SERVER_URL,
    layers: 'hel:orto1988'
now_layer = new L.BingLayer "AuLflCabjUYZCzLW7RP4eUi2aF_8r071tR8PycPuJIQ-n9-Tb2QYTYpjRdQl_iy8"

orto_layers = [
    orto1943_layer, orto1964_layer, orto1976_layer, orto1988_layer, now_layer
]
orto_years = [
    1943, 1964, 1976, 1988, 2012
]

osm_roads_layer = L.tileLayer.wms WMS_SERVER_URL,
    layers: 'osm:planet_osm_line'
    format: 'image/png'
    transparent: true

marker = null
input_addr_map = null

$("#address-input").typeahead(
    source: (query, process_cb) ->
        url_query = encodeURIComponent(query)
        $.getJSON(GEOCODER_URL + 'v1/address/?format=json&name=' + url_query, (data) ->
            objs = data.objects
            ret = []
            input_addr_map = []
            for obj in objs
                ret.push(obj.name)
            input_addr_map = objs
            process_cb(ret)
        )
)
        
nearby_markers = []

find_nearby_addresses = (target_coords) ->
    url = GEOCODER_URL + "v1/address/?format=json&lat=#{target_coords[0]}&lon=#{target_coords[1]}"
    $.getJSON(url, (data) ->
        objs = data.objects
        el = $("#nearby-addr-list")
        el.empty()
        for m in nearby_markers
            map.removeLayer m
        nearby_markers = []
        index = 1
        for addr in objs
            name = addr.name
            distance = Math.round(addr.distance)
            coords = addr.location.coordinates
            m = new L.Marker [coords[1], coords[0]],
                icon: new L.NumberedDivIcon {number: index.toString()}
            m.addTo map
            nearby_markers.push m
            el.append($("<li>#{addr.name} #{distance} m</li>"))
            index++
    )
$("#address-input").on 'change', ->
    match_obj = null
    for obj in input_addr_map
        if obj.name == $(this).val()
            match_obj = obj
            break
    if not match_obj
        return
    coords = obj.location.coordinates
    if not marker
        marker = L.marker([coords[1], coords[0]],
            draggable: true
        )
        marker.on 'dragend', (e) ->
            coords = marker.getLatLng()
            find_nearby_addresses([coords.lat, coords.lng])
        marker.addTo(map)
    else
        marker.setLatLng([coords[1], coords[0]])
    map.setView([coords[1], coords[0]], 17)

input_district_map = null
$("#district-input").typeahead(
    source: (query, process_cb) ->
        $.getJSON(GEOCODER_URL + 'v1/district/', {input: query}, (data) ->
            objs = data.objects
            ret = []
            input_addr_map = []
            for obj in objs
                ret.push(obj.name)
            input_district_map = objs
            process_cb(ret)
        )
)


$("#district-input").on 'change', ->
    match_obj = null
    for obj in input_district_map
        if obj.name == $(this).val()
            match_obj = obj
            break
    if not match_obj
        return
    borders = L.geoJson match_obj.borders,
        style:
            weight: 2
            fillOpacity: 0.08
    borders.bindPopup match_obj.name
    borders.addTo map
    map.fitBounds borders.getBounds()

show_plans = false

map.on 'moveend', (ev) ->
    if not show_plans
        return
    if map.getZoom() < 13
        return
    if plan_current_xfer
        plan_current_xfer.abort()
        plan_current_xfer = null
    refresh_plans()

default_style =
    weight: 2
    color: "blue"

default_dev_style =
    weight: 2
    color: "red"

hover_style =
    color: "orange"

plan_click = (ev) ->

plan_hover_start = (ev) ->
    @.setStyle hover_style

plan_hover_end = (ev) ->
    if @.in_effect
        @.setStyle default_style
    else
        @.setStyle default_dev_style

plans = {}
draw_plans = (new_plans) ->
    for obj in new_plans
        if obj.id of plans
            continue
        plans[obj.id] = obj
        geom = L.geoJson obj.geometry
        geom.in_effect = obj.in_effect
        if geom.in_effect
            geom.setStyle default_style
        else
            geom.setStyle default_dev_style
        geom.bindPopup "Kaava nr. <b>#{obj.origin_id}</b>"
        geom.on 'mouseover', plan_hover_start
        geom.on 'mouseout', plan_hover_end
        geom.addTo map
        obj.geom = geom

plan_refresher = null
refresh_plans = ->
    if plan_refresher
        plan_refresher.abort()
    plan_refresher = new PlanRefresher()
    plan_refresher.fetch()

class PlanRefresher
    constructor: ->
        @should_abort = false
        @current_xfer = null
    abort: ->
        @should_abort = true
        if @current_xfer?
            @current_xfer.abort()
    fetch: ->
        bounds = map.getBounds().toBBoxString()
        url = GEOCODER_URL + 'v1/plan/'

        params =
            bbox: bounds
            limit: 100

        receive_plans = (data) =>
            if @should_abort
                return
            draw_plans data.objects
            next = data.meta.next
            if next
                @current_xfer = $.getJSON next, receive_plans

        @current_xfer = $.getJSON url, params, receive_plans

$("#show-plans").on 'click', ->
    if show_plans
        for plan_id of plans
            plan = plans[plan_id]
            map.removeLayer plan.geom
        plans = {}
        show_plans = false
        $("#show-plans").html 'Show plans'
        return
    show_plans = true
    if map.getZoom() < 13
        map.setZoom 13
        # refresh_plans() will be called automatically through the 'moveend' event.
    else
        refresh_plans()
    $("#show-plans").html 'Hide plans'

N_STEPS = 100
MIN_OPACITY = 0.4

layer_count = orto_layers.length
slider_max = (layer_count - 1) * N_STEPS

slider = $("#slider").slider
    max: slider_max
    value: slider_max
    tooltip: 'hide'

current_state = {}


initialize_years = ->
    $year_list = $("#year_list")
    y_width = $year_list.width() / orto_years.length
    y_width -= 20
    for y in orto_years
        s = $("<div>#{y}</div>")
        s.css
            "font-size": "24px"
            "width": y_width
            "float": "left"
            "margin-left": "20px"
            "opacity": MIN_OPACITY
        $year_list.append s

initialize_years()

update_years = (year_a_idx, opacity) ->
    for year_el, idx in $("#year_list div")
        if idx == year_a_idx
            opa = opacity * (1 - MIN_OPACITY)
        else if idx == year_a_idx + 1
            opa = (1 - opacity) * (1 - MIN_OPACITY)
        else
            opa = 0
        $(year_el).css {"opacity": MIN_OPACITY + opa}

draw_screen = (val) ->
    if val == current_state.val
        return
    current_state.val = val
    layer_a_idx = Math.floor val / N_STEPS
    if val == slider_max
        layer_a_idx = layer_count - 2

    layer_b_op = (val % N_STEPS) / N_STEPS
    if val == (layer_a_idx + 1) * N_STEPS
        layer_b_op = 1.0

    visible_layers = [orto_layers[layer_a_idx], orto_layers[layer_a_idx+1]]
    visible_layers[0].setOpacity 1 - layer_b_op
    visible_layers[1].setOpacity layer_b_op
    current_state.visible_layers = visible_layers

    update_years layer_a_idx, 1 - layer_b_op

    $("#year_a").html orto_years[layer_a_idx]
    $("#year_b").html orto_years[layer_a_idx + 1]
    $("#year_a").css {opacity: 1 - layer_b_op}
    $("#year_b").css {opacity: layer_b_op}

    for al in orto_layers
        match = false
        for l in visible_layers
            if l == al
                match = true
                break
        if not match
            al.setOpacity 0
            al.visible = false
        else
            al.visible = true

    for l in visible_layers
        if not l.added
            l.addTo map
            l.added = true

slider.on 'slide', (ev) ->
    val = ev.value
    draw_screen val

# When the map starts moving, remove all non-visible layers
# to save on bandwidth cost.
map.on "movestart", (ev) ->
    for l in orto_layers
        if not l.visible and l.added
            map.removeLayer l
            l.added = false

draw_screen slider_max
