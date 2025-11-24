require 'feedjira'
require 'httparty'
require 'jekyll'

module ExternalPosts
  class ExternalPostsGenerator < Jekyll::Generator
    safe true
    priority :high

    def generate(site)
      sources = site.config['external_sources']
      return if sources.nil? || sources.empty?

      sources.each do |src|
        name = src['name'] || 'external source'
        url  = src['rss_url']

        Jekyll.logger.info "ExternalPosts:", "Fetching external posts from #{name}: #{url}"

        begin
          resp = HTTParty.get(
            url,
            headers: {
              "User-Agent" => "Mozilla/5.0 (GitHub Actions; Jekyll)",
              "Accept"     => "application/rss+xml, application/xml;q=0.9, */*;q=0.8"
            },
            timeout: 15
          )

          xml = resp.body.to_s

          # Quick sanity check: Medium sometimes returns HTML/403 pages
          unless xml.lstrip.start_with?("<")
            raise "Empty or non-XML response"
          end
          if xml =~ /<!doctype html>/i || xml =~ /<html/i
            raise "Got HTML instead of RSS (likely blocked or wrong URL)"
          end

          feed = Feedjira.parse(xml)
          entries = feed.respond_to?(:entries) ? feed.entries : []

          if entries.empty?
            Jekyll.logger.warn "ExternalPosts:", "No entries found for #{name}"
            next
          end

          entries.each do |e|
            next unless e.respond_to?(:url) && e.url

            Jekyll.logger.debug "ExternalPosts:", "...fetching #{e.url}"

            title = e.title.to_s.strip
            slug  = title.downcase.gsub(/\s+/, '-').gsub(/[^\w-]/, '')
            slug  = "external-post" if slug.empty?

            path = site.in_source_dir("_posts/#{slug}.md")
            doc = Jekyll::Document.new(
              path, { site: site, collection: site.collections['posts'] }
            )

            doc.data['external_source'] = name
            doc.data['feed_content']    = e.respond_to?(:content) ? e.content : nil
            doc.data['title']           = title
            doc.data['description']     = e.respond_to?(:summary) ? e.summary : nil
            doc.data['date']            = e.respond_to?(:published) ? e.published : Time.now
            doc.data['redirect']        = e.url

            site.collections['posts'].docs << doc
          end

        rescue Feedjira::NoParserAvailable => ex
          Jekyll.logger.warn "ExternalPosts:", "Skipping #{name}: not valid RSS/XML (#{ex.message})"
          next
        rescue StandardError => ex
          Jekyll.logger.warn "ExternalPosts:", "Skipping #{name}: #{ex.class} #{ex.message}"
          next
        end
      end
    end
  end
end
