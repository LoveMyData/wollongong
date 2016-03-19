require "mechanize"
require 'scraperwiki'

# This is using the ePathway system.

class WollongongScraper
  attr_reader :agent

  def initialize
    @agent = Mechanize.new
  end

  def extract_urls_from_page(page)
    content = page.at('table.ContentPanel')
    if content
      content.search('tr')[1..-1].map do |app|
        (page.uri + app.search('td')[0].at('a')["href"]).to_s
      end
    else
      []
    end
  end

  # The main url for the planning system which can be reached directly without getting a stupid session timed out error
  def enquiry_url
    "http://epathway.wollongong.nsw.gov.au/ePathway/Production/Web/GeneralEnquiry/EnquiryLists.aspx"
  end

  # Returns a list of URLs for all the applications on exhibition
  def urls
    # Get the main page and ask for the list of DAs on exhibition
    page = agent.get(enquiry_url)
    form = page.forms.first
    form.radiobuttons[0].click
    page = form.submit(form.button_with(:value => /Save and Continue/))

    page_label = page.at('#ctl00_MainBodyContent_mPagingControl_pageNumberLabel')
    if page_label.nil?
      # If we can't find the label assume there is only one page of results
      number_of_pages = 1
    elsif page_label.inner_text =~ /Page \d+ of (\d+)/
      number_of_pages = $~[1].to_i
    else
      raise "Unexpected form for number of pages"
    end
    urls = []
    (1..number_of_pages).each do |page_no|
      # Don't refetch the first page
      if page_no > 1
        page = agent.get("http://epathway.wollongong.nsw.gov.au/ePathway/Production/Web/GeneralEnquiry/EnquirySummaryView.aspx?PageNumber=#{page_no}")
      end
      # Get a list of urls on this page
      urls += extract_urls_from_page(page)
    end
    urls
  end

  def extract_field(field, label)
    raise "unexpected form" unless field.search('td')[0].inner_text == label
    field.search('td')[1].inner_text.strip
  end

  def applications
    urls.map do |url|
      # Get application page with a referrer or we get an error page
      page = agent.get(url, [], URI.parse(enquiry_url))
      table = page.search('#ctl00_MainBodyContent_DynamicTable > tr')[0].search('td')[0].search('table').last

      date_received = extract_field(table.search('tr')[0], "Lodgement Date")
      day, month, year = date_received.split("/").map{|s| s.to_i}
      application_id = extract_field(table.search('tr')[2], "Application Number")
      description = extract_field(table.search('tr')[3], "Proposal").squeeze(" ").strip

      table = page.search('table#ctl00_MainBodyContent_DynamicTable > tr')[2].search('td')[0].search('table').last
      address = table.search(:tr)[1].at(:td).inner_text

      record = {
        "date_received" => Date.new(year, month, day).to_s,
        "council_reference" => application_id,
        "description" => description,
        "address" => address,
        "info_url" => enquiry_url,
        "comment_url" => enquiry_url,
        "date_scraped" => Date.today.to_s
      }
      #p record
      if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
        ScraperWiki.save_sqlite(['council_reference'], record)
      else
        puts "Skipping already saved record " + record['council_reference']
      end
    end
  end
end

WollongongScraper.new.applications
