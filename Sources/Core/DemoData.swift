#if DEBUG
import Foundation

/// Synthetic fixtures for screenshots and layout work. Debug builds only: launch with `--demo [--tool <rawValue>]`.
/// All people and companies here are made up.
enum DemoData {
    static func response(for tool: Tool) -> JSON? {
        let text: String
        switch tool {
        case .peopleSearch: text = people
        case .peopleEnrich: text = enrich
        case .webSearch: text = web
        case .news: text = news
        case .answers: text = answers
        case .scrape: text = scrape
        case .map: text = map
        case .crawl: text = crawl
        case .companySearch: text = companies
        case .brand: text = brand
        case .styleguide: text = styleguide
        case .parse: text = parse
        }
        guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return JSON(any: obj)
    }

    static let people = """
    {"results":[
     {"name":"Maya Okafor","description":"Revenue leader scaling go-to-market teams at climate hardware companies.","profiles":["https://linkedin.com/in/maya-okafor-demo","https://github.com/mokafor-demo"],
      "location":{"country_code":"US","region":"California","city":"Sacramento"},
      "role":{"title":"VP of Sales","seniority":"vp","functions":["sales","business development"],"started_on":"2022-03","company":{"name":"Helio Grid","domain":"heliogrid.example"}},
      "years_of_experience":14,"is_founder":false,"skills":["Enterprise sales","Channel partnerships","Forecasting","Solar PV","Negotiation","Team building"],"schools":["UC Davis"]},
     {"name":"Tomás Rivera","description":"Founder turned operator. Sold residential solar into three states.","profiles":["https://linkedin.com/in/tomas-rivera-demo"],
      "location":{"country_code":"US","region":"California","city":"San Diego"},
      "role":{"title":"Chief Revenue Officer","seniority":"c_suite","functions":["sales"],"started_on":"2021-09","company":{"name":"Sunlit Roofs","domain":"sunlitroofs.example"}},
      "years_of_experience":18,"is_founder":true,"skills":["Revenue operations","Pricing","Fundraising"],"schools":["San Diego State University","Stanford GSB"]}
    ],"next_cursor":"demo","key_metadata":{"credits_consumed":10,"credits_remaining":988},"request_id":"demo-people"}
    """

    static let enrich = """
    {"match":{"status":"candidate","score":91,"person":{
      "name":{"full":"Maya Okafor","first":"Maya","last":"Okafor"},"email":"maya@heliogrid.example",
      "bio":"Revenue leader scaling go-to-market teams at climate hardware companies. Previously built the channel program at Photon & Co.",
      "location":{"display":"Sacramento, California, United States","city":"Sacramento","region":"California","country":"United States","country_code":"US"},
      "social_urls":["https://linkedin.com/in/maya-okafor-demo","https://github.com/mokafor-demo"],"website_urls":["https://mayaokafor.example"],
      "current_role":{"title":"VP of Sales","organization":{"name":"Helio Grid","domain":"heliogrid.example"},"is_current":true,"start_date":{"year":2022,"month":3}},
      "current_role_status":"present",
      "experience":[
       {"title":"VP of Sales","organization":{"name":"Helio Grid","domain":"heliogrid.example"},"location":"Remote","description":"Owns a 40-person revenue team across direct and channel. Took ARR from $12M to $48M in three years.","start_date":{"year":2022,"month":3},"is_current":true},
       {"title":"Director, Channel Sales","organization":{"name":"Photon & Co"},"location":"San Francisco, CA","description":"Built the partner program from zero to 120 installers.","start_date":{"year":2017,"month":6},"end_date":{"year":2022,"month":2}},
       {"title":"Account Executive","organization":{"name":"Brightside Energy"},"start_date":{"year":2012,"month":8},"end_date":{"year":2017,"month":5}}],
      "education":[{"institution":{"name":"UC Davis"},"degree":"B.S.","field_of_study":"Managerial Economics","start_date":{"year":2008},"end_date":{"year":2012}}],
      "skills":["Enterprise sales","Channel partnerships","Forecasting","Solar PV","Negotiation","Team building","Pipeline management"],
      "last_updated":"2026-09-30T12:00:00Z","checked_at":"2026-10-24T05:00:00Z"}},
     "key_metadata":{"credits_consumed":20,"credits_remaining":968},"request_id":"demo-enrich"}
    """

    static let web = """
    {"query":"open source map tile servers","results":[
     {"url":"https://github.com/maplibre/martin","title":"maplibre/martin: Blazing fast and lightweight PostGIS vector tiles server","description":"Martin is a tile server able to generate and serve vector tiles on the fly from large PostgreSQL databases, as well as from PMTiles and MBTiles files.","relevance":"high",
      "markdown":{"code":"SUCCESS","markdown":"# Martin\\n\\nA **fast** tile server.\\n\\n- PostGIS sources\\n- PMTiles and MBTiles\\n- Sprites and fonts\\n\\n## Quick start\\n\\n```\\nmartin postgres://user@host/db\\n```\\n\\n> Serves vector tiles on the fly.\\n\\n1. Install\\n2. Run\\n3. Point your map at it"},
      "highlights":{"code":"SUCCESS","highlights":["Martin is a tile server able to generate and serve vector tiles on the fly from large PostgreSQL databases.","It can also combine tiles from several sources into a single composite tileset."]}},
     {"url":"https://openmaptiles.org/","title":"OpenMapTiles: Open vector tile schema and tools","description":"OpenMapTiles is an extensible and open vector tile schema for a OpenStreetMap basemap.","relevance":"high","markdown":{"code":"NOT_REQUESTED","markdown":null},"highlights":{"code":"NOT_REQUESTED","highlights":null}},
     {"url":"https://wiki.openstreetmap.org/wiki/Tile_servers","title":"Tile servers - OpenStreetMap Wiki","description":"A tile server is a piece of software that serves raster or vector map tiles to clients.","relevance":"medium","markdown":{"code":"NOT_REQUESTED","markdown":null},"highlights":{"code":"NOT_REQUESTED","highlights":null}}
    ],"cache_metadata":{"status":"miss","age_ms":0},"key_metadata":{"credits_consumed":1,"credits_remaining":987},"request_id":"demo-web"}
    """

    static let news = """
    {"data":[
     {"id":"1","story_id":"s1","url":"https://example.com/solar-record","title":"Solar installers report record quarter as battery attach rates climb","description":"Residential installers across California posted their strongest quarter on record, driven by storage demand and falling hardware costs.","language":"en","authors":["Priya Nair"],"image_url":null,"published_at":"2026-10-22T14:30:00Z","type":"editorial","source":{"name":"Example Energy Weekly","domain":"example.com","direct":true},"match":{"level":"primary","confidence":0.94}},
     {"id":"2","story_id":"s2","url":"https://example.org/helio-grid-series-c","title":"Helio Grid raises $90M Series C to expand utility-scale tracking","description":"The round was led by a climate-focused growth fund.","language":"en","authors":[],"image_url":null,"published_at":"2026-10-20T09:00:00Z","type":"press_release","source":{"name":"Example Wire","domain":"example.org","direct":false},"match":{"level":"secondary","confidence":0.7}}
    ],"has_more":true,"next_cursor":"demo","meta":{"count":2},"key_metadata":{"credits_consumed":1,"credits_remaining":986},"request_id":"demo-news"}
    """

    static let answers = """
    {"json_content":{"summary":"Context.dev is a web-data API covering scraping, search, brand and people data.","founded":2024,"products":["Web search","Scrape","Crawl","Brand intelligence","People enrichment"],"pricing":{"model":"credits","free_tier":true}},
     "sources":["https://docs.context.dev","https://www.context.dev"],"key_metadata":{"credits_consumed":10,"credits_remaining":976},"request_id":"demo-answers"}
    """

    static let scrape = """
    {"url":"https://example.com/post","markdown":{"requested":true,"success":true,"data":"# A short post\\n\\nSome *inline* text with a [link](https://example.com).\\n\\n- one\\n- two"},
     "html":{"requested":false,"success":null,"data":null},"screenshot":{"requested":false,"success":null,"data":null},
     "images":{"requested":true,"success":true,"data":[{"url":"https://example.com/a.png","alt":"Diagram","width":800,"height":600,"classification":"illustration"}]},
     "highlights":{"requested":false,"success":null,"data":null},"json":{"requested":false,"success":null,"data":null},"product":{"requested":false,"success":null,"data":null},
     "metadata":{"title":"A short post","description":"An example page.","language":"en","siteName":"Example","canonicalUrl":"https://example.com/post","headings":[{"level":1,"text":"A short post"},{"level":2,"text":"Details"}],"keywords":["example","demo"]},
     "key_metadata":{"credits_consumed":2,"credits_remaining":974},"request_id":"demo-scrape"}
    """

    static let map = """
    {"success":true,"domain":"example.com","urls":[
     {"url":"https://example.com/","title":"Example","description":"Home page"},
     {"url":"https://example.com/pricing","title":"Pricing","description":"Plans and credits"},
     {"url":"https://example.com/docs/getting-started","title":"Getting started"}],
     "key_metadata":{"credits_consumed":1,"credits_remaining":973},"request_id":"demo-map"}
    """

    static let crawl = """
    {"results":[
     {"markdown":"# Home\\n\\nWelcome.","metadata":{"sourceUrl":"https://example.com/","finalUrl":"https://example.com/","title":"Home","crawlDepth":0,"statusCode":200,"success":true,"url":"https://example.com/"}},
     {"markdown":"# Pricing\\n\\n- Free\\n- Pro","metadata":{"sourceUrl":"https://example.com/pricing","finalUrl":"https://example.com/pricing","title":"Pricing","crawlDepth":1,"statusCode":200,"success":true,"url":"https://example.com/pricing"}}],
     "metadata":{"numUrls":2,"maxCrawlDepth":1,"numSucceeded":2,"numFailed":0,"numSkipped":0},"key_metadata":{"credits_consumed":2,"credits_remaining":971},"request_id":"demo-crawl"}
    """

    static let companies = """
    {"results":[
     {"name":"Helio Grid","domain":"heliogrid.example","description":"Single-axis solar trackers and the software that runs them.","organization_type":"private","operating_status":"active","stock_symbols":[],
      "revenue":{"min_usd":50000000,"max_usd":100000000},"industries":["Renewable energy","Hardware","Software"],"founded_year":2016,
      "headquarters":{"country_code":"US","region":"California","city":"Sacramento"},"employees":{"count":null,"min":201,"max":500},
      "funding":{"total_usd":210000000,"round_count":4,"stage":"Series C","latest_round":{"type":"Series C","date":"2026-10-20","amount_usd":90000000},
       "rounds":[{"type":"Series C","date":"2026-10-20","amount_usd":90000000},{"type":"Series B","date":"2023-04-11","amount_usd":75000000},{"type":"Seed","date":"2019-01-15","amount_usd":8000000}]}},
     {"name":"Sunlit Roofs","domain":"sunlitroofs.example","description":"Residential solar installation across the Southwest.","organization_type":"private","operating_status":"active","stock_symbols":["SUNL"],
      "revenue":{"min_usd":10000000,"max_usd":50000000},"industries":["Solar","Construction"],"founded_year":2014,"headquarters":{"country_code":"US","region":"California","city":"San Diego"},
      "employees":{"count":340,"min":null,"max":null},"funding":{"total_usd":null,"round_count":0,"stage":null,"latest_round":null,"rounds":[]}}
    ],"next_cursor":null,"key_metadata":{"credits_consumed":2,"credits_remaining":969},"request_id":"demo-companies"}
    """

    static let brand = """
    {"status":"ok","code":200,"brand":{"domain":"stripe.com","title":"Stripe","slogan":"Building programmable financial services.",
     "description":"Stripe is a global financial infrastructure platform that enables businesses of all sizes to accept payments, manage billing, and access banking services.",
     "logo":"https://media.brand.dev/4e779806-8622-480b-b3bb-aaa5fe88bdde.svg",
     "colors":[{"hex":"#533afd","name":"Meteor Shower"},{"hex":"#ae9cfc","name":"Shy Moment"},{"hex":"#040404","name":"Armor Wash"}],
     "socials":[{"type":"x","url":"https://x.com/stripe"},{"type":"github","url":"https://github.com/stripe"},{"type":"linkedin","url":"https://linkedin.com/company/stripe"}],
     "industries":{"eic":[{"industry":"Finance","subindustry":"Payments & Money Movement"},{"industry":"Finance","subindustry":"Financial Infrastructure & APIs"}]},
     "links":[{"label":"Contact","url":"https://stripe.com/contact/sales"},{"label":"Pricing","url":"https://stripe.com/pricing"},{"label":"Careers","url":"https://stripe.com/careers"}],
     "email":"hello@stripe.example","location":"South San Francisco, CA, US"},
     "key_metadata":{"credits_consumed":10,"credits_remaining":959},"request_id":"demo-brand"}
    """

    static let styleguide = """
    {"domain":"example.com","styleguide":{"mode":"light","colors":{"accent":"#ff6b14","background":"#ffffff","text":"rgb(17, 24, 39)"},
     "typography":{"headings":{
       "h1":{"fontFamily":"Georgia","fontFallbacks":["serif"],"fontSize":"48px","fontWeight":700,"lineHeight":"56px","letterSpacing":"-0.02em"},
       "h2":{"fontFamily":"Georgia","fontFallbacks":["serif"],"fontSize":"32px","fontWeight":600,"lineHeight":"40px","letterSpacing":"-0.01em"},
       "h3":{"fontFamily":"Helvetica Neue","fontFallbacks":["sans-serif"],"fontSize":"24px","fontWeight":600,"lineHeight":"32px","letterSpacing":"0"}},
      "p":{"fontFamily":"Helvetica Neue","fontFallbacks":["sans-serif"],"fontSize":"16px","fontWeight":400,"lineHeight":"24px","letterSpacing":"0"}},
     "elementSpacing":{"xs":"4px","sm":"8px","md":"16px","lg":"32px","xl":"64px"},
     "shadows":{"sm":"0 1px 2px rgba(0,0,0,.08)","md":"0 4px 12px rgba(0,0,0,.12)","lg":"0 12px 32px rgba(0,0,0,.16)","xl":"0 24px 64px rgba(0,0,0,.2)","inner":"inset 0 1px 2px rgba(0,0,0,.1)"},
     "fontLinks":{},
     "components":{"button":{
       "primary":{"backgroundColor":"#ff6b14","color":"#ffffff","borderColor":"transparent","borderRadius":"10px","borderWidth":"0px","padding":"12px 20px","fontSize":"16px","fontWeight":600,"css":"background:#ff6b14;color:#fff;border-radius:10px"},
       "secondary":{"backgroundColor":"transparent","color":"#ff6b14","borderColor":"#ff6b14","borderRadius":"10px","borderWidth":"1px","padding":"12px 20px","fontSize":"16px","fontWeight":600,"css":"border:1px solid #ff6b14"}},
      "card":{"backgroundColor":"#fafafa","borderColor":"#e5e7eb","borderRadius":"16px","borderWidth":"1px","padding":"24px","textColor":"#111827","css":"border-radius:16px"}}},
     "key_metadata":{"credits_consumed":10,"credits_remaining":949},"request_id":"demo-style"}
    """

    static let parse = """
    {"success":true,"type":"pdf","markdown":"# Quarterly report\\n\\nRevenue grew **14%** quarter over quarter.\\n\\n- North America: 62%\\n- Europe: 28%\\n- Other: 10%","key_metadata":{"credits_consumed":1,"credits_remaining":948},"request_id":"demo-parse"}
    """
}
#endif
