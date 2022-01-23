require 'qiita'
require 'net/http'
require 'json'

token = ENV['QIITA_ACCESS_TOKEN']
team_domain = ARGV[0] # qiita team のドメイン
query = ARGV[1].present? ? ARGV[1] : nil # 検索条件
per_page = ARGV[2].present? ? ARGV[2].to_i : 5 # 1リクエストあたりの記事取得件数(最大100)
request_max = ARGV[3].present? ? ARGV[3].to_i : 1 # リクエスト回数
page_offset = ARGV[4].present? ? ARGV[4].to_i : 1 # ページの取得開始位置

host = "#{team_domain}.#{Qiita::Client::DEFAULT_HOST}"
unless host
  puts "APIトークンを環境変数にエクスポートしてから実行してください。"
  puts "例）"
  puts "export QIITA_ACCESS_TOKEN='APIトークン'"
  exit
end

unless team_domain
  puts "第１引数にQiita teamの固有ドメイン部分を指定してください。(.qiita.comは不要)"
  puts "第２引数は検索クエリです。Qiita teamでの検索条件をそのまま入れられます。"
  puts "ただし、空白を含む場合はダブルクオートで囲ってください"
  puts '例) "group:group1 test"'
  puts "検索条件を指定しない場合は、ダブルクオート2つを設定してください。"
  puts "第３引数は1リクエストあたりの記事取得件数です。(デフォルトは5, 最大は100)"
  puts "第４引数はリクエスト回数です。(デフォルトは1)"
  puts "第５引数はページの取得開始位置です。(デフォルトは1)"
  exit
end

client = Qiita::Client.new(access_token: token, host: host)
csv = "#, Group, Title, Tags, Qiita URL\n" # 出力ファイル一覧
offset = (page_offset - 1) * per_page # 通し番号のオフセット
count = 0 # 現在の記事数
request_cnt = 0 # 現在のリクエスト回数
page = page_offset

loop do
  params = {
    'per_page' => per_page,
    'page' => page
  }
  params['query'] = query if query
  begin
    items = client.list_items(params).body
  rescue Exception => e
    puts "#{page}ページ目のデータ取得でQiita APIの呼び出しに失敗しました。エラー内容：#{e.message}"
    puts "ここまでの結果をCSVに出力して処理を終了します"
    break
  end
  request_cnt += 1
  if items.empty?
    puts "データがもう存在しません。現在のページ番号:#{page}, 現在のデータのindex:#{count + offset}"
    break
  end
  # puts items # デバッグ用

  items.each do |response|
    qbody = response['body']
    org_title = response['title']
    title = org_title.gsub(/\//, '／') #半角/を全角／に置換
    puts title
    org_group_name = response['group'] ? response['group']['name'] : 'グループなし'
    group_name = org_group_name.gsub(/\//, '／') #半角/を全角／に置換

    groupdir = "./#{group_name}"
    FileUtils.mkdir(groupdir) unless File.exist?(groupdir)

    count += 1
    dirindex = format("%d", count + offset)
    article_path = "#{groupdir}/#{dirindex}_#{title}"
    FileUtils.mkdir(article_path) unless File.exist?(article_path)

    json_path = "#{article_path}/#{title}_meta.json"
    File.write(json_path, JSON.pretty_generate(response))

    qbody_path = "#{article_path}/#{title}.md"
    org_title.gsub!(/,/, '，') #半角カンマを全角カンマに置換

    tags = response['tags']
    tags_str = ''
    tags.each do |tag|
      tags_str += tag['name'] + ' / '
    end

    csv += format("%s, %s, %s, %s, %s\n", dirindex, org_group_name, org_title, tags_str, response['url'])

    images = qbody.scan(/!\[image\..*\]\((.*)\)/)
    images = qbody.scan(/src=\"(.*)\"/) if images.empty?

    images.flatten!

    https = Net::HTTP.new(host, 443)
    https.use_ssl = true

    # img をダウンロード
    images.each do |url|
      # puts url # デバッグ用
      begin
        uri = URI.parse(url)
        open("#{article_path}/#{File.basename(uri.path)}", 'wb') do |file|
          req = Net::HTTP::Get.new(uri)
          req["Authorization"] = "Bearer #{token}"
          file.puts(https.request(req).body)
        end
      rescue Exception => e
        puts "画像のダウンロードに失敗しました。画像のパス:#{url} "
        puts e.message
      end
    end
    File.write(qbody_path, qbody)
  end
  page += 1
  break if request_cnt >= request_max
end

csv_name = "./#{team_domain}"
csv_name += "_#{query}" if query
csv_name += "_#{per_page}" if per_page
csv_name += "_#{request_max}" if request_max
csv_name += "_#{page_offset}" if page_offset
File.write("#{csv_name}.csv", csv)

puts "処理完了！！ #{page_offset}ページ目から#{page - 1}ページ目まで取得しました。"
