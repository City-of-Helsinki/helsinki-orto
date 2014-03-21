crs = null

init_map = ->
    crs_name = 'EPSG:3879'
    proj_def = '+proj=tmerc +lat_0=0 +lon_0=25 +k=1 +x_0=25500000 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'

    bounds = [25440000, 6630000, 25571072, 6761072]
    crs = new L.Proj.CRS.TMS crs_name, proj_def, bounds,
        resolutions: [256, 128, 64, 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625]

    map = new L.Map 'map',
        crs: crs
        continuusWorld: true
        worldCopyJump: false
        zoomControl: true

    return map

map = init_map()
map.setView [60.171944, 24.941389], 7
hash = new L.Hash map

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
    geoserver_url = (layer_name, layer_fmt) ->
        "http://geoserver.hel.fi/geoserver/gwc/service/tms/1.0.0/#{layer_name}@ETRS-GK25@#{layer_fmt}/{z}/{x}/{y}.#{layer_fmt}"

    orto_layer = new L.Proj.TileLayer.TMS geoserver_url("hel:orto#{year}", "jpg"), crs,
        maxZoom: 11
        minZoom: 2
        continuousWorld: true
        tms: false

    return orto_layer

orto_years = [
    1932, 1943, 1950, 1964, 1976, 1988, 2012
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
osm_roads_layer.setOpacity 0.6
osm_roads_layer.setZIndex 5

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
window.show_roads = false

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
    ###if not window.show_orto
        for l in orto_layers
            if not l.added
                continue
            map.removeLayer l
            l.added = false
        if not osm_layer.added
            
            osm_layer.addTo map
        return
    ###
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
    else
        return

    # if the keypress is for the map element, do not process it here.
    target = $(ev.target)
    if target.closest("#map").length
        return
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

display_building_modal = (feat) ->
    $(".modal").remove()
    modal = $("""
    <div class="modal hide fade" tabindex="-1" role="dialog" aria-hidden="true">
        <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-hidden="true">×</button>
            <h3>#{feat.address}</h3>
        </div>
        <div class="modal-body">
            <table class="table table-striped"><tbody>
            </tbody></table>
        </div>
        <div class="modal-footer">
            <button class="btn" data-dismiss="modal" aria-hidden="true">Sulje</button>
        </div>
    </div>
    """)
    $("body").append modal
    $tbody = modal.find 'tbody'
    for prop, val of feat.properties
        if not val
            continue
        if typeof val != 'string' and typeof val != 'number'
            continue
        arr = window.rakennukset_meta[prop.toLowerCase()]
        prop_name = ""
        if arr
            prop_name = arr[1]
        if not prop_name
            prop_name = prop
        $el = $("<tr><td>#{prop_name}</td><td>#{val}</td></tr>")
        $tbody.append $el
    modal.modal('show')

refresh_buildings = ->
    if map.getZoom() < 8 or not window.show_buildings
        if building_layer
            map.removeLayer building_layer
            building_layer = null
        return
    str = map.getBounds().toBBoxString() + ',EPSG:4326'
    get_wfs 'hel:rakennukset',
        maxFeatures: 500
        bbox: str
        propertyName: 'valmvuosi,osoite,kayttotark_taso3,wkb_geometry_s2'
        , (data) ->
            if building_layer
                map.removeLayer building_layer
            building_layer = L.geoJson data,
                style: building_styler
                onEachFeature: (feat, layer) ->
                    year = feat.properties.valmvuosi
                    address = feat.properties.osoite
                    if address
                        address = address.replace /(\d){5} [A-Z]+/, ""
                    use = feat.properties.kayttotark_taso3
                    if use
                        use = use.replace /(\d)+ /, ""
                    popup = $("<div></div>")
                    popup.append $("<b>Valm.vuosi #{year}</b><br/>#{use}<br/><b>#{address}</b><br/>")
                    button = $("<button class='btn btn-primary'>Näytä lisätietoja</button>")
                    button.css
                        "margin-top": "20px"
                    popup.append button
                    button.click ->
                        get_wfs 'hel:rakennukset',
                            featureID: feat.id
                        , (data) ->
                            obj = data.features[0]
                            obj.address = address
                            display_building_modal obj
                    layer.bindPopup popup[0]
            building_layer.addTo map

map.on 'moveend', refresh_buildings

$(".readmore").click ->
    $(".moreinfo").slideDown()
    $(this).hide()

BuildingControl = L.Control.extend
    click: ->
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
    options:
        position: 'topright'
    onAdd: (map) ->
        $button = $('<button id="show-buildings-btn" class="btn btn-success">Näytä rakennukset</button>')
        $button.click @.click
        return $button[0]

new BuildingControl().addTo map

RoadsControl = L.Control.extend
    click: ->
        if window.show_roads
            $(this).html "Näytä tiet"
            $(this).addClass "btn-success"
            $(this).removeClass "btn-danger"
            map.removeLayer osm_roads_layer
        else
            $(this).html "Piilota tiet"
            $(this).removeClass "btn-success"
            $(this).addClass "btn-danger"
            map.addLayer osm_roads_layer

        window.show_roads = not window.show_roads
    options:
        position: 'topright'
    onAdd: (map) ->
        $button = $('<button id="show-roads-btn" class="btn btn-success">Näytä tiet</button>')
        $button.click @.click
        return $button[0]

new RoadsControl().addTo map
