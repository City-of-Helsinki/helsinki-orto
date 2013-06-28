map = L.map('map').setView([60.171944, 24.941389], 15)

osm_layer = L.tileLayer('http://{s}.tile.cloudmade.com/BC9A493B41014CAABB98F0471D759707/999/256/{z}/{x}/{y}.png',
    maxZoom: 18,
    attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, <a href="http://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="http://cloudmade.com">CloudMade</a>'
)

get_wfs = (type, args, callback) ->
    url = GEOSERVER_BASE_URL + 'wfs/'
    params =
        service: 'WFS'
        version: '1.1.0'
        request: 'GetFeature'
        typeName: type
        srsName: 'EPSG:4326'
        outputFormat: 'application/json'
    for key of args
        params[key] = args[key]
    $.getJSON url, params, callback

make_tile_layer = (year) ->
    opts =
        tms: true
    layer = L.tileLayer GWC_BASE_URL + "tms/1.0.0/hel:orto#{year}@EPSG:900913@jpeg/{z}/{x}/{y}.jpeg", opts
    return layer

orto_years = [
    1943, 1964, 1976, 1988, 2012
]
orto_layers = (make_tile_layer year for year in orto_years)
###
orto2012_layer = L.tileLayer.wms 'http://kartta.hel.fi/wms/code4europe.mapdef',
    layers: 'Ortoilmakuva_05cm_2012'
    format: 'image/jpeg'
    attribution: '&copy;Kaupunkimittausosasto, Helsinki 01/2013'
orto_layers[orto_layers.length - 1] = orto2012_layer
###

osm_roads_layer = L.tileLayer.wms GWC_BASE_URL + "wms/",
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
active_district = null

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
    if not $(this).val().length
        if active_district
            map.removeLayer active_district
            active_district = null
        return

    for obj in input_district_map
        if obj.name == $(this).val()
            match_obj = obj
            break
    if not match_obj
        return

    if active_district
        map.removeLayer active_district
    borders = L.geoJson match_obj.borders,
        style:
            weight: 2
            fillOpacity: 0.08
    borders.bindPopup match_obj.name
    borders.addTo map
    map.fitBounds borders.getBounds()
    active_district = borders

window.show_buildings = false
window.show_orto = true

N_STEPS = 100
MIN_OPACITY = 0.2

layer_count = orto_layers.length
slider_max = (layer_count - 1) * N_STEPS

current_state = {}

update_years = (state) ->
    year_a_idx = state.layer_a_idx
    opacity = 1 - state.layer_b_opacity
    for year_el, idx in $("#year_list div")
        if idx == year_a_idx
            opa = opacity * (1 - MIN_OPACITY)
        else if idx == year_a_idx + 1
            opa = (1 - opacity) * (1 - MIN_OPACITY)
        else
            opa = 0
        $(year_el).css {"opacity": MIN_OPACITY + opa}

calculate_year_data = (val) ->
    layer_a_idx = Math.floor val / N_STEPS
    if val == slider_max
        layer_a_idx = layer_count - 2
    layer_b_op = (val % N_STEPS) / N_STEPS
    if val == (layer_a_idx + 1) * N_STEPS
        layer_b_op = 1.0
    # Figure out the year between the two orto imagery years.
    year_a = orto_years[layer_a_idx]
    diff = orto_years[layer_a_idx + 1] - year_a
    year = Math.round year_a + diff * layer_b_op

    return {layer_a_idx: layer_a_idx, layer_b_opacity: layer_b_op, year: year}

redraw_buildings = ->
    if not building_layer
        return
    building_layer.setStyle building_styler

update_screen = (val, force_refresh) ->
    if not window.show_orto
        for l in orto_layers
            if not l.added
                continue
            map.removeLayer l
            l.added = false
        if not osm_layer.added
            
            osm_layer.addTo map
        return
    if not force_refresh and val == current_state.val
        return
    current_state.val = val
    state = calculate_year_data val
    current_state.layer_a_idx = state.layer_a_idx
    visible_layers = [orto_layers[state.layer_a_idx], orto_layers[state.layer_a_idx+1]]
    visible_layers[0].setOpacity 1 - state.layer_b_opacity
    visible_layers[1].setOpacity state.layer_b_opacity
    current_state.visible_layers = visible_layers
    if current_state.year != year
        current_state.year = year
        year_changed = true
    else
        year_changed = false

    update_years state

    $("#year_a").html orto_years[state.layer_a_idx]
    $("#year_b").html orto_years[state.layer_a_idx + 1]
    $("#year_a").css {opacity: 1 - state.layer_b_opacity}
    $("#year_b").css {opacity: state.layer_b_opacity}

    $("#current_year").html year

    # Set visibility flags on all layers and hide the non-visible layers.
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

    # Add the visible layers that haven't yet been added.
    for l in visible_layers
        if not l.added
            l.addTo map
            l.added = true

    if year_changed
        redraw_buildings()


# When the map starts moving, remove all non-visible layers
# to save on bandwidth cost.
map.on "movestart", (ev) ->
    for l in orto_layers
        if not l.visible and l.added
            map.removeLayer l
            l.added = false


slider = $("#slider").slider
    max: slider_max
    value: slider_max
    tooltip: 'hide'

slider.on 'slide', (ev) ->
    val = ev.value
    update_screen val


select_year = (idx) ->
    val = idx * N_STEPS
    slider.slider 'setValue', val
    update_screen val

initialize_years = ->
    $year_list = $("#year_list")
    y_width = $year_list.width() / orto_years.length
    for y, idx in orto_years
        $text_el = $("<div>#{y}</div>")
        $text_el.css
            "font-size": "24px"
            "width": y_width
            "float": "left"
            "opacity": MIN_OPACITY
            "text-align": "center"
            "cursor": "pointer"
        $text_el.data "index", idx
        $text_el.click ->
            idx = $(@).data 'index'
            select_year idx
        $year_list.append $text_el

initialize_years()

$(document).keydown (ev) ->
    val = current_state.val
    idx = Math.floor val / N_STEPS
    if ev.keyCode == 37 # left arrow
        idx = idx - 1
        if idx < 0
            idx = 0
    else if ev.keyCode == 39 # right arrow
        idx = idx + 1
        if idx == layer_count
            idx = layer_count - 1
    select_year idx

update_screen slider_max

colors = ['#feedde', '#fdd0a2', '#fdae6b', '#fd8d3c', '#f16913', '#d94801', '#8c2d04']

building_styler = (feat) ->
    ret =
        weight: 1
        opacity: 1.0
        fillOpacity: 0.4
    year = parseInt feat.properties.valmvuosi
    if current_state.year and year > current_state.year
        ret.opacity = 0
        ret.fillOpacity = 0
    if not year or year == 9999
        color = '#eee'
    else
        start_year = 1890
        end_year = new Date().getFullYear()
        if year < start_year
            year = start_year
        n = Math.floor (year - start_year) * colors.length / (end_year - start_year)
        n = colors.length - n - 1
        color = colors[n]
    ret.color = color
    return ret

building_layer = null

refresh_buildings = ->
    if map.getZoom() < 16 or not window.show_buildings
        if building_layer
            map.removeLayer building_layer
            building_layer = null
        return
    str = map.getBounds().toBBoxString() + ',EPSG:4326'
    get_wfs 'hel:rakennukset',
        maxFeatures: 500
        bbox: str
        propertyName: 'valmvuosi,osoite,wkb_geometry_s2'
        , (data) ->
            if building_layer
                map.removeLayer building_layer
            building_layer = L.geoJson data,
                style: building_styler
                onEachFeature: (feat, layer) ->
                    year = feat.properties.valmvuosi
                    address = feat.properties.osoite
                    layer.bindPopup "<b>Valm.vuosi #{year}</b><br/>#{address}"
            building_layer.addTo map

map.on 'moveend', refresh_buildings

$("#show-buildings-btn").click ->
    if window.show_buildings
        $(this).html "Näytä rakennukset"
        $(this).addClass "btn-success"
        $(this).removeClass "btn-danger"
    else
        $(this).html "Piilota rakennukset"
        $(this).removeClass "btn-success"
        $(this).addClass "btn-danger"

    window.show_buildings = not window.show_buildings
    refresh_buildings()

$("#show-orto-btn").click ->
    if not window.show_orto
        $(this).html "Piilota ilmakuva"
    else
        $(this).html "Näytä ilmakuva"
    window.show_orto = not window.show_orto
    update_screen current_state.val, true

$(".readmore").click ->
    $(".moreinfo").slideDown()
    $(this).hide()
