## totally simple proof of concept game for the [wikidata distributed game](http://tools.wmflabs.org/wikidata-game/distributed)

It tries to match municipality of Germany (Q262166) with their respective administrative territorial entity (P131).
For that, it extracts the administrative territorial entity (P131) from the municipality description - or if nothing matches,
from the "Infobox Gemeinde in Deutschland" template in the linked dewiki article.

It doesn't implement a storage of tiles or declined tiles intentionally. So every request for tiles triggers queries to wikidata and the dewiki articles.
Without storage/caching features, you should not add something based on this code to the list of public accessible wikidata games.

**How to run:**
Install the Gems listed in the Gemfile with `bundle install` and run the server with `bundle exec ruby app.rb`.

Then, make it reachable from the public internet. Put it on an public IP or forward connections with tools like [ngrok](https://ngrok.com).

Open the wikidata distributed game and click "add your own!". Now you should get a form for testing your game.
Enter the URL `http://your.host.example/api`.

**License:** CC-0 (Creative Commons Zero)