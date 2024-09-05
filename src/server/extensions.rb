class Hash
  def to_s
    JSON.pretty_generate(self)
  end
end

class String
  def to_html
    "<p>#{self}</p>\n"
  end
end
