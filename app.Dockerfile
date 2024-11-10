FROM ruby:3.1-alpine

RUN apk add --no-cache build-base

WORKDIR /app

COPY app/Gemfile .
RUN bundle add rackup
RUN bundle install

COPY app .

CMD ["ruby", "app.rb"]

EXPOSE 4567
