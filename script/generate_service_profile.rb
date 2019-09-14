SERVICE_PROFILE = <<~YAML
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: quan-io-service.quan-io.svc.cluster.local
  namespace: quan-io
spec:
  routes:
  - condition:
      method: GET
      pathRegex: /
    name: GET /
  - condition:
      method: GET
      pathRegex: /about/
    name: GET /about/
  - condition:
      method: GET
      pathRegex: /blog/
    name: GET /blog/
  - condition:
      method: GET
      pathRegex: /img/favicon\.ico
    name: GET /img/favicon.ico
YAML

Dir["content/blog/*"].each do |markdown|
  title = File.readlines(markdown)
    .find { |line| line.start_with?("title: ") }
    .split(": ")[1]
    .chomp
    .downcase
    .gsub(" ", "-")
    .gsub(/'|,|"/, "")

  SERVICE_PROFILE << <<-YAML
  - condition:
      method: GET
      pathRegex: /blog/#{title}/
    name: GET /blog/#{title}/
  YAML
end

puts SERVICE_PROFILE
