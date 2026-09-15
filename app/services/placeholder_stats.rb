# Invented walker counts and ratings for the community route cards.
#
# These are demo numbers, deliberately: only one walk in the whole database
# carries a rating, so the real figures (Journey#walker_count and #rating, both
# of which still exist and are still tested) leave almost every card blank.
# Kept until there is enough real data to show instead.
#
# Derived from the primary key so a given route always shows the same numbers
# rather than changing on every render -- the point is for the cards to look
# populated, and a route whose rating moved each time you looked at it would be
# worse than one with no rating at all.
#
# To switch the app over to the real figures, the whole change is in two views:
# community_routes/index.html.erb and community_routes/show.html.erb, swapping
# placeholder_walker_count/placeholder_rating for walker_count/rating_display.
# Then delete this file.
module PlaceholderStats
  module_function

  def walker_count(id)
    40 + (id % 120)
  end

  def rating(id)
    (3.8 + ((id % 5) * 0.2)).round(1)
  end
end
