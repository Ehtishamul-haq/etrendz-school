json.array!(@courses) do |course|
  json.extract! course, :id, :course_name, :section_name
  json.url course_url(course, format: :json)
end
