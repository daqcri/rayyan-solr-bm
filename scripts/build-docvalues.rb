require 'rubygems'
require 'rsolr'
require 'progress_bar'
require 'faker'

url = 'http://localhost:8983/solr/docvalues'
total_documents = 2_000_000
batch_size = 1000
solr = RSolr.connect :url => url
pb = ProgressBar.new(total_documents)

# clean index
solr.delete_by_query '*:*'
solr.commit

get_rand_arr = proc {|l|
  (1..(l || 5)).map{rand*10_000_000}
}

get_rand_txt_arr = proc{|l|
  Faker::Lorem.paragraphs(l || 3)
}

# batch insert synthetic data
1.upto(total_documents / batch_size) do |n|
  failed = true

  # retry failed requests
  while failed do
    begin
      # prepare array
      min_id, max_id = (n-1)*batch_size+1, n*batch_size
      docs = (min_id..max_id).map{|i|
        doc = {
          id: i,
          attrib_docvalues: get_rand_arr.call.map(&:round),
          attrib_nodocvalues: get_rand_arr.call.map(&:round)
        }
        3.times{|i| doc["noisy#{i}_is"] = get_rand_arr.call.map(&:round)}
        3.times{|i| doc["noisy#{i}_ss"] = get_rand_arr.call.map(&:to_s)}
        3.times{|i| doc["noisy#{i}_ds"] = get_rand_arr.call}
        3.times{|i| doc["noisy#{i}_en"] = get_rand_txt_arr.call}
        doc 
      }
      # send a request to add docs
      solr.add docs
      # soft commit every 100 batches
      solr.commit(commit_attributes: {softCommit: true}) if n%100 == 0
      # indicate new progress
      pb.increment! batch_size
      failed = false
    rescue
    end
  end
end

# hard commit when done
solr.commit
