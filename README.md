# StreamChat MockServer

## Install dependencies:

```bash
bundle install
```

## Sync mock server with real backend:

```bash
bundle exec ruby sync.rb
```

## Run mock server for manual testing:

```bash
bundle exec ruby src/server.rb
```

## Run mock server for automated testing:

```bash
bundle exec ruby driver.rb
