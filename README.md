# StreamChat MockServer

## Run mock server for manual testing:

```bash
bundle exec ruby src/server.rb
```

## Run mock server for automated testing:

```bash
# before test suite
bundle exec ruby driver.rb &

# before each test
curl "localhost:4567/start"

# after each test
curl "localhost:4567/stop"

# after test suite
lsof -t -i:4567 | xargs kill -9
```
