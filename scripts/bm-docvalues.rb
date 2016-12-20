require 'rubygems'
require 'rsolr'
require 'benchmark'
require 'json'

url = 'http://localhost:8983/solr/docvalues'

all_facets = {
  "attrib_docvalues" => {
    "f.attrib_docvalues.facet.mincount" => 1,
    "f.attrib_docvalues.facet.limit" => 100
  },
  "attrib_nodocvalues" => {
    "f.attrib_nodocvalues.facet.mincount" => 1,
    "f.attrib_nodocvalues.facet.limit" => 100
  }
}

base_params = {
  "start" => 0,
  "rows" => 0,
  "facet" => "true",
  "q" => "*:*",
  "!cache" => false,
  "wt" => "json"
}

solr = RSolr.connect :url => url

all_facets.keys.each do |facet|
  params = {"facet.field" => facet}
    .merge(base_params)
    .merge(all_facets[facet])

  failed = true

  # retry failed requests (they are inevitable!)
  while failed do
    begin
      b = Benchmark.measure(facet) {
        # send a request to /select
        response = solr.get 'select', :params => params
        # json = JSON.parse(response)
      }
      puts "#{b.real}\t#{b.label}"
      failed = false
    rescue
    end
  end

end
