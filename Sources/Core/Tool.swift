import Foundation

enum ToolGroup: String, CaseIterable, Identifiable {
    case people = "People"
    case web = "Web"
    case companies = "Companies & Brands"
    case files = "Files"

    var id: String { rawValue }
    var tools: [Tool] { Tool.allCases.filter { $0.group == self } }
}

enum Tool: String, CaseIterable, Identifiable {
    case peopleSearch, peopleEnrich
    case webSearch, news, answers, scrape, map, crawl
    case companySearch, brand, styleguide
    case parse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peopleSearch: "Find People"
        case .peopleEnrich: "Identify a Person"
        case .webSearch: "Web Search"
        case .news: "News"
        case .answers: "Answers"
        case .scrape: "Scrape a Page"
        case .map: "Map a Site"
        case .crawl: "Crawl a Site"
        case .companySearch: "Find Companies"
        case .brand: "Brands"
        case .styleguide: "Style Guide"
        case .parse: "Parse a File"
        }
    }

    var symbol: String {
        switch self {
        case .peopleSearch: "person.2.fill"
        case .peopleEnrich: "person.text.rectangle.fill"
        case .webSearch: "globe"
        case .news: "newspaper.fill"
        case .answers: "sparkles"
        case .scrape: "doc.text.magnifyingglass"
        case .map: "point.3.connected.trianglepath.dotted"
        case .crawl: "ant.fill"
        case .companySearch: "building.2.fill"
        case .brand: "paintpalette.fill"
        case .styleguide: "textformat.size"
        case .parse: "doc.richtext.fill"
        }
    }

    var group: ToolGroup {
        switch self {
        case .peopleSearch, .peopleEnrich: .people
        case .webSearch, .news, .answers, .scrape, .map, .crawl: .web
        case .companySearch, .brand, .styleguide: .companies
        case .parse: .files
        }
    }

    var blurb: String {
        switch self {
        case .peopleSearch: "Describe who you're after by role, employer, place or skills and get profiles back."
        case .peopleEnrich: "Pin down one specific person from whatever clues you have: a name, an email, a profile link."
        case .webSearch: "Ranked web results, with optional highlights and full page content for each."
        case .news: "Live and historical news about a topic, or about a single company."
        case .answers: "Ask a research question and get a sourced answer in the shape you choose."
        case .scrape: "Capture one page as Markdown, HTML, a screenshot, structured JSON and more."
        case .map: "List every URL on a site, from its sitemap and links."
        case .crawl: "Follow links across a site and read each page as Markdown."
        case .companySearch: "Find companies by industry, size, place, funding or \"companies like…\"."
        case .brand: "Look up a company's logos, colours, socials and details, or find a brand by name."
        case .styleguide: "Pull a website's design system: colours, type, spacing and components."
        case .parse: "Turn a PDF, Word, Excel, PowerPoint, image or text file into clean Markdown."
        }
    }

    var cost: String {
        switch self {
        case .peopleSearch: "10 credits per page"
        case .peopleEnrich: "20 credits per match"
        case .webSearch: "1 credit per 10 results"
        case .news: "1 credit per 10 results"
        case .answers: "10 credits (fast) or 100 (ultra)"
        case .scrape: "From 1 credit"
        case .map: "1 credit (2 with search)"
        case .crawl: "1 credit per page"
        case .companySearch: "2 credits per page"
        case .brand: "1 credit to search, 10 to retrieve"
        case .styleguide: "10 credits"
        case .parse: "1 credit per file"
        }
    }

    /// What the primary button says.
    var verb: String {
        switch self {
        case .peopleSearch, .webSearch, .news, .companySearch: "Search"
        case .peopleEnrich: "Identify"
        case .answers: "Ask"
        case .scrape: "Scrape"
        case .map: "Map"
        case .crawl: "Crawl"
        case .brand: "Look Up"
        case .styleguide: "Extract"
        case .parse: "Parse"
        }
    }
}

/// A request from one tool to open another with fields filled in (e.g. "look up this company's brand").
struct Handoff: Equatable {
    let id = UUID()
    let tool: Tool
    let values: [String: String]
    let run: Bool
}
