import express, { Request, Response } from "express";
import { exec } from "child_process";
import axios from "axios";
import querystring from "querystring";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const app = express();
const SPOTIFY_CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
const SPOTIFY_CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
const PLAYERCTL_INSTANCE =
  process.env.PLAYERCTL_INSTANCE || "chromium.instance3";

let spotifyToken: string | null = null;

interface NowPlayingData {
  artist: string;
  title: string;
  coverUrl: string;
}

async function getSpotifyToken(): Promise<string> {
  if (spotifyToken) return spotifyToken;

  if (!SPOTIFY_CLIENT_ID || !SPOTIFY_CLIENT_SECRET) {
    throw new Error(
      "Spotify credentials are not set in the environment variables.",
    );
  }

  const response = await axios.post<{ access_token: string }>(
    "https://accounts.spotify.com/api/token",
    querystring.stringify({
      grant_type: "client_credentials",
    }),
    {
      headers: {
        Authorization:
          "Basic " +
          Buffer.from(SPOTIFY_CLIENT_ID + ":" + SPOTIFY_CLIENT_SECRET).toString(
            "base64",
          ),
        "Content-Type": "application/x-www-form-urlencoded",
      },
    },
  );
  spotifyToken = response.data.access_token;
  return spotifyToken;
}

async function getNowPlaying(): Promise<NowPlayingData> {
  return new Promise((resolve, reject) => {
    exec(
      `playerctl -p ${PLAYERCTL_INSTANCE} metadata --format "{{ artist }} - {{ title }}"`,
      async (error, stdout, stderr) => {
        if (error) {
          console.error(`exec error: ${error}`);
          reject("An error occurred");
          return;
        }
        let [artist, title] = stdout.trim().split(" - ");
        artist = artist.split(",")[0].trim();
        title = title.replace(/-$/, "").trim();
        console.log(`Cleaned metadata: Artist: ${artist}, Title: ${title}`);
        try {
          const token = await getSpotifyToken();
          const searchUrl = `https://api.spotify.com/v1/search?q=${encodeURIComponent(
            artist + " " + title,
          )}&type=track&limit=1`;
          const searchResponse = await axios.get<{
            tracks: {
              items: Array<{ album: { images: Array<{ url: string }> } }>;
            };
          }>(searchUrl, {
            headers: { Authorization: "Bearer " + token },
          });
          let coverUrl = "";
          if (searchResponse.data.tracks.items.length > 0) {
            coverUrl = searchResponse.data.tracks.items[0].album.images[0].url;
          }
          resolve({ artist, title, coverUrl });
        } catch (searchError) {
          console.error("Error fetching album cover:", searchError);
          reject("Error fetching data");
        }
      },
    );
  });
}

app.use(express.static(path.join(__dirname, "..", "public")));

app.get("/now-playing", (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, "..", "public", "now-playing.html"));
});

app.get("/now-playing-data", async (req: Request, res: Response) => {
  try {
    const data = await getNowPlaying();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: "Error fetching data" });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
