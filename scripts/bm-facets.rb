#!/usr/bin/env ruby
require 'rubygems'
require 'rsolr'
require 'benchmark'
require 'highline'
require 'dotenv'

class SolrFacetsBenchmarker

  def cli_menu_deployment(cli)
    cli.choose do |menu|
      menu.prompt = "Please choose solr deployment: "
      menu.choice("development (default)") {
        @url = 'http://localhost:8982/solr/development'
        @review_id = 124
        @search_ids = [782, 783]
      }
      menu.choice("websolr-staging") {
        assign_solr_url 'SOLR_WEBSOLR_STAGING_URL'
        @review_id = 90
        @search_ids = [176]
        cli_menu_websolr_prefer cli
      }
      menu.choice("websolr-prod") {
        assign_solr_url 'SOLR_WEBSOLR_PRODUCTION_URL'
        @review_id = 16
        @search_ids = [41]
        cli_menu_websolr_prefer cli
      }
      menu.choice("measured-staging") {
        assign_solr_url 'SOLR_MEASURED_STAGING_URL'
        @review_id = 13
        @search_ids = [13]
      }
      menu.choice("measured-prod-noshards") {
        assign_solr_url 'SOLR_MEASURED_PRODUCTION_NOSHARDS_URL'
        @review_id = 4
        @search_ids = [16]
      }
      menu.choice("measured-prod-shards") {
        assign_solr_url 'SOLR_MEASURED_PRODUCTION_SHARDS_URL'
        @review_id = 4
        @search_ids = [16]
      }
      menu.choice("own-hosting-production") {
        assign_solr_url 'SOLR_OWNHOSTING_PRODUCTION_NONSECURE_URL'
        @review_id = 4
        @search_ids = [16]
      }
      menu.choice("own-hosting-production (SSL)") {
        assign_solr_url 'SOLR_OWNHOSTING_PRODUCTION_URL'
        @review_id = 4
        @search_ids = [16]
      }
      menu.default = :development
    end
    @search_ids << -1
    cli_menu_facet_type cli
  end

  def cli_menu_websolr_prefer(cli)
    cli.choose do |menu|
      menu.prompt = "Prefer master or slave: "
      menu.choices(:master, :slave) { |c|
        @prefer = c
      }
      menu.default = :master
    end
  end

  def cli_menu_facet_type(cli)
    cli.choose do |menu|
      menu.prompt = "Choose facet field types: "
      menu.choices(:global, :replicated) { |c|
        @facet_type = c
      }
    end
  end

  def initialize
    Dotenv.load
    cli_menu_deployment HighLine.new

    dk = ":r#{@review_id}" if @facet_type == :replicated
    @all_facets = {
      "language#{dk}_s" => {
        "f.language#{dk}_s.facet.mincount" => 1
      },
      "publication_types#{dk}_im" => {
        "f.publication_types#{dk}_im.facet.mincount" => 1
      },
      "locations#{dk}_im" => {
        "f.locations#{dk}_im.facet.limit" => 30,
        "f.locations#{dk}_im.facet.mincount" => 1
      },
      "keyphrases#{dk}_im" => {
        "f.keyphrases#{dk}_im.facet.limit" => 30,
        "f.keyphrases#{dk}_im.facet.mincount" => 1
      },
      "journal#{dk}_i" => {
        "f.journal#{dk}_i.facet.limit" => 100,
        "f.journal#{dk}_i.facet.mincount" => 1
      },
      "authors#{dk}_im" => {
        "f.authors#{dk}_im.facet.limit" => 100,
        "f.authors#{dk}_im.facet.mincount" => 1
      },
      "year#{dk}_i" => {
        "f.year#{dk}_i.facet.limit" => 30,
        "f.year#{dk}_i.facet.mincount" => 1
      },
      "abstract_languages#{dk}_sm" => {
        "f.abstract_languages#{dk}_sm.facet.mincount" => 1
      },
      "features#{dk}_im" => {
        "f.features#{dk}_im.facet.mincount" => 1
      },
      "has_public_fulltexts_bs" => {
        "f.has_public_fulltexts_bs.facet.mincount" => 1
      },
      "has_private_fulltexts:has_fulltext_#{@review_id}_1_bs" => {
        "f.has_private_fulltexts:has_fulltext_#{@review_id}_1_bs.facet.mincount" => 1
      },
      "user_customization_keys:flags_#{@review_id}_1_sms"  => {
        "f.user_customization_keys:flags_#{@review_id}_1_sms.facet.mincount" => 1
      }
    }

    @base_params = {
      "fq" => ["type:Article", "search_im:(#{@search_ids.join(' OR ')})"],
      "start" => 0,
      "rows" => 0,
      "facet" => "true",
      "q" => "*:*"
    }

    @solr = RSolr.connect :url => @url

  end #initialize

  def start
    # Test all combinations of facets
    print_header
    max_combinations = [(ENV['MAX_COMBINATIONS'] || "999").to_i, @all_facets.keys.length].min
    repeat = (ENV['REPEAT_REQUESTS'] || "1").to_i
    1.upto(max_combinations) do |n|
      $stderr.puts "[#{n} combinations]" if n > 1
      @all_facets.keys.combination(n) do |filtered_facets|
        params = {"facet.field" => filtered_facets}.merge(@base_params)
        filtered_facets.each do |facet|
          params.merge!(@all_facets[facet])
        end
        i, t_min, t_max, t_avg = 0, -1, -1, 0.0
        1.upto(repeat) do
          t = request(params)
          t_min = t if t < t_min || t_min < 0
          t_max = t if t > t_max || t_max < 0
          t_avg = t_avg * i / (i+1) + t / (i+1)
          i += 1
        end
        puts "#{t_min.round(2)}\t#{t_avg.round(2)}\t#{t_max.round(2)}\t#{filtered_facets.join(',')}"
      end
    end
  end #start

  def print_header
    puts "\nmin\tavg\tmax\tfacets"
  end

  def request(params)
    remaining_attempts, backoff = 6, 1
    loop do
      begin
        remaining_attempts -= 1
        b = Benchmark.measure {
          response = @solr.get 'select', :params => params, :headers => {"X-Websolr-Routing" => "prefer-#{@prefer}"}
        }
        return b.real*1000
      rescue => e
        raise e if remaining_attempts == 0
        $stderr.puts "Error: #{e.class}: sleeping for #{backoff} second(s) before retyring..."
        sleep backoff
        backoff <<= 1
      end
    end
  end #request

private

  def assign_solr_url(env)
    @url = ENV[env]
    unless @url
      puts "Error: Environment variable not found: #{env}, exiting"
      exit 1
    end
  end

end #class

SolrFacetsBenchmarker.new.start
