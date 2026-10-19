"""Let beets write MusicBrainz IDs and nothing else.

MusicBrainz matching is only trusted for identity. Its artist credits, titles,
dates and genres can be wrong for artists that share a name, so they are
stripped from every tag write and the file keeps what it already had.
"""

from beets.plugins import BeetsPlugin


class IdsOnlyPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.register_listener("write", self.only_ids)

    @staticmethod
    def only_ids(item, path, tags):
        for key in list(tags):
            if not key.startswith("mb_"):
                del tags[key]
