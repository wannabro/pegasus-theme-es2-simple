// This file contains some helper scripts for formatting data


// For multiplayer games, show the player count as '1-N'
function formatPlayers(playerCount) {
    if (playerCount === 1)
        return playerCount

    return "1-" + playerCount;
}


// Show dates in Y-M-D format
function formatDate(date) {
    return Qt.formatDate(date, "yyyy-MM-dd");
}


// Show last played time as text. Based on the code of the default Pegasus theme.
// Note to self: I should probably move this into the API.
function formatLastPlayed(lastPlayed) {
    if (isNaN(lastPlayed))
        return "never";

    var now = new Date();

    var elapsedHours = (now.getTime() - lastPlayed.getTime()) / 1000 / 60 / 60;
    if (elapsedHours < 24 && now.getDate() === lastPlayed.getDate())
        return "today";

    var elapsedDays = Math.round(elapsedHours / 24);
    if (elapsedDays <= 1)
        return "yesterday";

    return elapsedDays + " days ago"
}


// Display the play time (provided in seconds) with text.
// Based on the code of the default Pegasus theme.
// Note to self: I should probably move this into the API.
function formatPlayTime(playTime) {
    var minutes = Math.ceil(playTime / 60)
    if (minutes <= 90)
        return Math.round(minutes) + " minutes";

    return parseFloat((minutes / 60).toFixed(1)) + " hours"
}


// Screen aspect ratio of a system, by collection short name. Handhelds use
// their native resolution, TV based systems are 4:3 unless listed as 16:9.
var screenAspects = {
    "gb": 10 / 9, "gbc": 10 / 9, "gamegear": 10 / 9, "megaduck": 10 / 9,
    "gba": 3 / 2, "pokemini": 3 / 2,
    "nds": 4 / 3,            // videos usually show one 256x192 screen
    "3ds": 5 / 6,            // 400x240 over 320x240
    "psp": 16 / 9, "psvita": 16 / 9,
    "ngp": 20 / 19, "ngpc": 20 / 19,
    "wonderswan": 14 / 9, "wonderswancolor": 14 / 9,
    "atarilynx": 160 / 102, "lynx": 160 / 102,
    "virtualboy": 12 / 7,
    "supervision": 1,
    "arduboy": 2, "gameandwatch": 4 / 3,
    "switch": 16 / 9, "wiiu": 16 / 9, "ps3": 16 / 9, "ps4": 16 / 9,
    "xbox360": 16 / 9, "steam": 16 / 9, "pc": 16 / 9, "windows": 16 / 9,
    "android": 16 / 9
};

function screenAspect(shortName) {
    return screenAspects[shortName] || 4 / 3;
}

