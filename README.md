# SlackToHTML

Export your Slack group JSON archive to a HTML website.

You can see what the website will look like here: [http://slack.elixirhq.com/](http://slack.elixirhq.com/).

## How to use

You'll need to have [Elixir](http://elixir-lang.org/) installed on your machine and a Slack export (you can request one [here](https://my-team.slack.com/services/export)).

```
$ git clone git@github.com:stevedomin/slack_to_html.git
$ cd slack_to_html
$ mix deps.get
$ mix slack.html ./Elixir Slack export Dec 31 2015/
# this will generate HTML files in the output/ directory, upload them to a S3 or GC bucket
```

You can configure the output directory and the channels you want to ignore in `config/config.exs`

## Notes

* This was built for the Elixir Slack group so you will probably want to edit some of the templates and the stylesheet.
* I used `python -m SimpleHTTPServer` to serve the files in development.
* That i-stay-in-the-middle-of-the-page-footer is awful I know, need to work on it.
