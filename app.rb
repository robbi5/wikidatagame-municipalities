require 'rubygems'
require 'bundler'
require 'sinatra'
require 'sinatra/jsonp'
require 'wikidata'
require 'active_support/all'
require 'addressable'
require 'open-uri'
require 'digest/sha1'

# Adding websites

get '/' do
  'hello world'
end

METHODS = [:desc, :tiles, :log_action].freeze
$skip = []
$lkcache = {}

def desc
  {
    label: {
      en: 'German municipality: add administrative territorial entity',
      de: 'Gemeinden: füge übergeordnete Verwaltungseinheit hinzu'
    },
    description: {
      en: 'Adding located in the administrative territorial entity (P131) to instances of municipality of Germany (Q262166)',
      de: 'Füge liegt in der Verwaltungseinheit (P131) zu Gemeinden in Deutschland (Q262166) hinzu'
    },
    icon: '' # 'https://path.to/some/icon/120px.png'
  }
end

def tiles
  count = params[:num].try(:to_i) || 1
  lang = params[:lang] || 'en'

  # Bad timeouts here:
  # https://query.wikidata.org/#PREFIX%20wikibase%3A%20%3Chttp%3A%2F%2Fwikiba.se%2Fontology%23%3E%0APREFIX%20bd%3A%20%3Chttp%3A%2F%2Fwww.bigdata.com%2Frdf%23%3E%0APREFIX%20schema%3A%20%3Chttp%3A%2F%2Fschema.org%2F%3E%0APREFIX%20wd%3A%20%3Chttp%3A%2F%2Fwww.wikidata.org%2Fentity%2F%3E%0APREFIX%20wdt%3A%20%3Chttp%3A%2F%2Fwww.wikidata.org%2Fprop%2Fdirect%2F%3E%0APREFIX%20p%3A%20%3Chttp%3A%2F%2Fwww.wikidata.org%2Fprop%2F%3E%0APREFIX%20ps%3A%20%3Chttp%3A%2F%2Fwww.wikidata.org%2Fprop%2Fstatement%2F%3E%0APREFIX%20pq%3A%20%3Chttp%3A%2F%2Fwww.wikidata.org%2Fprop%2Fqualifier%2F%3E%0A%0ASELECT%20%3Fmunicipality%20%3FmunicipalityLabel%20%3FmunicipalityDesc%20%3Fstate%0AWHERE%0A%7B%0A%20%20%3Fmunicipality%20p%3AP31%20%3Fstatement%20.%0A%20%20%3Fstatement%20ps%3AP31%2Fwdt%3AP279*%20wd%3AQ262166%20.%0A%20%20FILTER%20NOT%20EXISTS%20%7B%20%3Fstatement%20pq%3AP582%20%3Fx%20%7D%20.%20%20%23%20Without%20already%20gone%20entries%20(end%20date)%0A%20%20FILTER%20NOT%20EXISTS%20%7B%20%3Fstatement%20pq%3AP576%20%3Fx%20%7D%20.%20%20%23%20Without%20already%20gone%20entries%20(dissolved)%0A%0A%20%20OPTIONAL%20%7B%0A%20%20%20%20%3Fmunicipality%20wdt%3AP131%2Fwdt%3AP131*%20%3Fqstate%20.%0A%20%20%20%20%3Fqstate%20wdt%3AP31%20wd%3AQ1221156%20.%0A%20%20%20%20%3Fqstate%20wdt%3AP300%20%3Fstate%20.%0A%20%20%7D%0A%0A%20%20FILTER%20(!BOUND(%3Fstate))%20%20%20%20%20%20%20%20%20%20%20%20%0A%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%20%0A%20%20SERVICE%20wikibase%3Alabel%20%7B%0A%20%20%20%20bd%3AserviceParam%20wikibase%3Alanguage%20%22de%22%20.%0A%20%20%20%20%3Fmunicipality%20schema%3Adescription%20%3FmunicipalityDesc%20.%0A%20%20%7D%0A%7D%0ALIMIT%2010
  query = <<-EOS.gsub(/^\s+/, '')
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX wd: <http://www.wikidata.org/entity/>
    PREFIX wdt: <http://www.wikidata.org/prop/direct/>
    PREFIX p: <http://www.wikidata.org/prop/>
    PREFIX ps: <http://www.wikidata.org/prop/statement/>
    PREFIX pq: <http://www.wikidata.org/prop/qualifier/>

    SELECT ?municipality ?municipalityLabel ?municipalityDescription ?dewiki ?state
    WHERE
    {
      ?municipality p:P31 ?statement .
      ?statement ps:P31 wd:Q262166 .
      FILTER NOT EXISTS { ?statement pq:P582 ?x } .  # Without already gone entries (end date)
      FILTER NOT EXISTS { ?statement pq:P576 ?x } .  # Without already gone entries (dissolved)

      SERVICE wikibase:label { bd:serviceParam wikibase:language "de" }

      ?municipality wdt:P856 ?website .

      ?dewiki schema:about ?municipality .
      ?dewiki schema:inLanguage "de" .
      ?dewiki schema:isPartOf <https://de.wikipedia.org/> .

      OPTIONAL {
        ?municipality wdt:P131/wdt:P131* ?qstate .
        ?qstate wdt:P31 wd:Q1221156 .
        ?qstate wdt:P300 ?state .
      }
      FILTER(!BOUND(?state))
    }
    LIMIT #{count + 10}
  EOS

  uri = Addressable::URI.parse('https://query.wikidata.org/bigdata/namespace/wdq/sparql')
  uri.query_values = { query: query, format: :json }

  resp = open(uri.normalize.to_s).read
  data = JSON.parse(resp)

  qs = data['results']['bindings'].map do |element|
    {
      q: element['municipality']['value'].gsub(%r{^http://www.wikidata.org/entity/}, ''),
      label: element['municipalityLabel']['value'],
      desc: element['municipalityDescription'].try(:[], 'value'),
      dewiki: element['dewiki']['value']
    }
  end

  puts qs.inspect

  client_cache = params[:in_cache].try(:split, ',')

  tiles = qs.map do |q|
    tileid = Digest::SHA1.hexdigest(q[:q])
    next nil if $skip.include? tileid
    next nil if !client_cache.nil? && client_cache.include?(tileid)

    item = Wikidata::Item.find_all_by_id(q[:q], sites: 'dewiki', languages: 'de').try(:first)
    next nil if item.nil?
    next nil unless item.entities_for_property_id('P131').empty?

    lk = lk_by_desc(q)
    wikiextract = extract_from_infobox(q)
    next nil if lk.nil? && wikiextract.nil?

    buttons = []
    sections = []
    buttons.concat lk[:buttons] unless lk.nil?
    sections.concat lk[:sections] unless lk.nil?
    buttons.concat wikiextract[:buttons] unless wikiextract.nil?
    sections.concat wikiextract[:sections] unless wikiextract.nil?

    {
      id: tileid,
      sections: [
        {
          type: 'item',
          q: q[:q]
        }
        # not useful, the game provides buttons to switch wikipedia excerpts
        # {
        #   type: 'wikipage',
        #   title: q[:label],
        #   wiki: 'dewiki'
        # }
      ].concat(sections.uniq),
      controls: [
        {
          type: 'buttons',
          entries: buttons.uniq.concat(
            [
              {
                type: 'white',
                decision: 'skip',
                label: 'Skip'
              }
            ])
        }
      ]
    }
  end

  {
    tiles: tiles.compact.first(count)
  }
end

def lk_by_desc(q)
  return nil if q[:desc].blank?

  m = q[:desc].match(/(?:Land)?[Kk]reis\s+(.+?)(?:[,\s]|\z)/)
  return nil unless m

  lk_by_name(m[1], q[:q])
end

def lk_by_name(name, entity)
  if $lkcache.key? name
    landkreis = $lkcache[name]
  else
    landkreis = lk_by_name_internal(name)
    $lkcache[name] = landkreis
  end

  return nil if landkreis.nil?

  id = landkreis.id.gsub(/^Q/, '').to_i

  {
    buttons: [
      {
        type: 'green',
        decision: 'yes',
        label: landkreis.label(:de),
        api_action: {
          action: 'wbcreateclaim',
          entity: entity,
          property: 'P131',
          snaktype: 'value',
          value: { 'entity-type' => 'item', 'numeric-id' => id }.to_json
        }
      }
    ],
    sections: [
      {
        type: 'item',
        q: landkreis.id
      }
    ]
  }
end

def lk_by_name_internal(name)
  uri = Addressable::URI.parse('https://www.wikidata.org/w/api.php')
  uri.query_values = { action: 'wbsearchentities', search: name, language: 'de', format: :json }

  url = uri.normalize.to_s

  resp = open(url).read
  data = JSON.parse(resp)

  if data['search'].blank?
    puts "#{url}: no result"
    return nil
  end

  ids = data['search'].map { |r| r['id'] }

  puts data['search'].map { |r| [r['id'], r['label'], r['description']].to_s }

  landkreise = Wikidata::Item.find_all_by_id(ids, sites: 'dewiki', languages: 'de')
  return nil if landkreise.nil?

  landkreis = landkreise.detect do |lk|
    lk.entities_for_property_id('P31').detect do |c|
      c.id == 'Q106658' || c.entities_for_property_id('P279').detect do |cc|
        cc.id == 'Q106658'
      end
    end
  end
  return nil if landkreis.nil?
  landkreis
end

def extract_from_infobox(q)
  dewiki = q[:dewiki]
  return nil if dewiki.blank?

  deuri = Addressable::URI.parse(dewiki)
  return nil unless deuri.host == 'de.wikipedia.org'

  title = deuri.normalize.basename.to_s
  title = URI.unescape(title)

  uri = Addressable::URI.parse('https://de.wikipedia.org/w/index.php')
  uri.query_values = { action: 'raw', title: title }

  url = uri.normalize.to_s

  resp = open(url).read
  unless resp.include? 'Infobox Gemeinde in Deutschland'
    puts "#{url}: No Infobox found"
    return nil
  end

  m = resp.match(/\{\{\s*Infobox Gemeinde in Deutschland\s*.*\|\s*Landkreis\s+=\s+([^\n]+)/m)
  return nil if m.nil?
  return nil if m[1].include? '['

  puts "#{url}: found: #{m[1]}"

  lk_by_name(m[1], q[:q])
end

def log_action
  tile = params[:tile]
  halt 201, '' if tile.blank?

  $skip << tile
end

def fail_with(message)
  status 400
  error = { error: message }
  halt jsonp(error)
end

get '/api' do
  fail_with 'action param missing' if params[:action].blank?

  method = params[:action].downcase.to_sym
  fail_with 'action unknown' unless METHODS.include? method

  data = send(method)

  jsonp data
end
