# 🌿 Moodwalk

Moodwalk suggests short walking routes near wherever you are based on how you're feeling, then lets you log your mood and a reflection once you're done.

_DROP SCREENSHOT HERE_
<br>
App home: https://moodwalk-ec6251edd332.herokuapp.com/

## Getting Started
### Setup

Install gems
```
bundle install
```

### ENV Variables
Create `.env` file
```
touch .env
```
Inside `.env`, set these variables. For any API keys, see group Slack channel.
```
MAPBOX_ACCESS_TOKEN=your_mapbox_access_token
GOOGLE_PLACES_API_KEY=your_google_places_api_key
CLOUDINARY_URL=your_own_cloudinary_url_key
OPENAI_API_KEY=your_openai_api_key
```

### DB Setup
This app uses PostgreSQL with the PostGIS extension (needed for location/map data) — make sure PostGIS is installed before running this.
```
rails db:create
rails db:migrate
rails db:seed
```

### Run a server
```
rails s
```
(or `bin/dev`, which this repo also has set up as a shortcut for the same thing)

## Built With
- [Rails 8](https://guides.rubyonrails.org/) - Backend / Front-end
- [Stimulus JS](https://stimulus.hotwired.dev/) - Front-end JS
- [Heroku](https://heroku.com/) - Deployment
- [PostgreSQL + PostGIS](https://postgis.net/) - Database
- [Bootstrap](https://getbootstrap.com/) — Styling
- [Mapbox](https://www.mapbox.com/) — Maps, walking directions, geocoding
- [Google Places API](https://developers.google.com/maps/documentation/places/web-service) — Finding real nearby places for each route

## Acknowledgements

Inspired by the walks we take when we don't really know where we want to go — only how we hope to feel when we come back.

MoodWalk explores a different relationship with navigation: less about the fastest way from A to B, and more about slowing down, wandering, noticing, and rediscovering the world around us.

## Team Members
- [Matthew Hardcastle](https://www.linkedin.com/in/matthew-hardcastle-7762123aa/)
- [Twinky Hung](https://www.linkedin.com/in/twinky-hung/)
- [Yusuke Kamihanawa](https://www.linkedin.com/in/cura-yjk/)

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change. See [`CLAUDE.md`](CLAUDE.md) for more in-depth technical notes about the codebase.

## License
This project is licensed under the MIT License
