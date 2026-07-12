chrome.runtime.onMessageExternal.addListener((request, sender, sendResponse) => {
  if (request.action === "fetchTemp") {
    const ip = request.ip;

    fetch(`http://${ip}:8005/rawTemp`)
      .then(response => {
        if (!response.ok) throw new Error(`HTTP status ${response.status}`);
        return response.text();
      })
      .then(data => sendResponse({ success: true, temp: data }))
      .catch(err => sendResponse({ success: false, error: err.message }));

    return true; // Keep message channel open for async fetch
  }

  // --- NEW IDLE SCREEN LOGIC ---
    if (request.action === "triggerIdleScreen") {
      const targetUrl = `http://${request.ip}:8005/idlescreen`;

      fetch(targetUrl, {
        method: 'POST', // Specifying the POST command
        headers: {
          'Content-Type': 'application/json'
        }
      })
      .then(response => {
        if (response.ok) {
          // Successfully triggered POST
          sendResponse({ success: true });
        } else {
          // The thermostat rejected the request (e.g., 404 or 500 error)
          sendResponse({ success: false, error: `HTTP Error: ${response.status}` });
        }
      })
      .catch(error => {
        // Network failed entirely (wrong IP, unreachable, etc.)
        sendResponse({ success: false, error: error.message });
      });

      return true; // Keeps the message channel open for the async fetch
    }

// --- NEW LED LOGIC ---
  if (request.action === "setLedRed") {
    const targetUrl = `http://${request.ip}:8005/led/animation/ALL_RED`;

    fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    })
    .then(response => {
      if (response.ok) {
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: `HTTP Error: ${response.status}` });
      }
    })
    .catch(error => sendResponse({ success: false, error: error.message }));

    return true; // Keep message channel open for async response
  }

  if (request.action === "setLedOff") {
    const targetUrl = `http://${request.ip}:8005/led/animation/NONE`;

    fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      }
    })
    .then(response => {
      if (response.ok) {
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: `HTTP Error: ${response.status}` });
      }
    })
    .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep message channel open for async response
  }
if (request.action === "fetchRunningEquipment") {
    const targetUrl = `http://${request.ip}:8005/running_equipment`;

    fetch(targetUrl, {
      method: 'GET'
    })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP status ${response.status}`);
      return response.json(); // Parse the JSON return
    })
    .then(data => {
      // Extract the array and format it as a comma-separated string
      const equipmentList = (data.equipment && Array.isArray(data.equipment))
          ? data.equipment.join(", ")
          : "None";

      sendResponse({ success: true, equipment: equipmentList });
    })
    .catch(err => sendResponse({ success: false, error: err.message }));

    return true; // Keep message channel open for async fetch
  }

  // --- NEW SCREENSHOT LOGIC ---
    if (request.action === "fetchScreenshot") {
      const targetUrl = `http://${request.ip}:8005/screenshot`;

      fetch(targetUrl, { method: 'GET' })
        .then(response => {
          if (!response.ok) throw new Error(`HTTP status ${response.status}`);
          return response.text(); // Parse as text to handle the <IMAGE> tags
        })
        .then(data => {
          // Use a regular expression to extract the hex string inside <IMAGE>...</IMAGE>
          const match = data.match(/<IMAGE>(.*?)<\/IMAGE>/);
          const hexData = match ? match[1] : data;

          sendResponse({ success: true, screenshotHex: hexData });
        })
        .catch(err => sendResponse({ success: false, error: err.message }));

      return true; // Keep message channel open for async fetch
    }

});