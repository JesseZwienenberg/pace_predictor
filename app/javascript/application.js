// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Function to get current location and populate lat/lng fields
window.getCurrentLocation = function() {
  if (navigator.geolocation) {
    const button = document.querySelector('.btn-location');
    const originalText = button.innerHTML;
    button.innerHTML = '📍 Getting location...';
    button.disabled = true;
    
    navigator.geolocation.getCurrentPosition(function(position) {
      document.getElementById('lat_field').value = position.coords.latitude;
      document.getElementById('lng_field').value = position.coords.longitude;
      button.innerHTML = originalText;
      button.disabled = false;
    }, function(error) {
      alert('Error getting location: ' + error.message);
      button.innerHTML = originalText;
      button.disabled = false;
    });
  } else {
    alert("Geolocation is not supported by this browser.");
  }
}

// Client-side filtering for segments results
document.addEventListener('DOMContentLoaded', function() {
  const filterDone = document.getElementById('filter-done');
  const filterFavorited = document.getElementById('filter-favorited');
  const table = document.getElementById('segments-table');
  
  if (filterDone && filterFavorited && table) {
    function applyFilters() {
      const showDoneOnly = filterDone.checked;
      const showFavoritedOnly = filterFavorited.checked;
      const rows = table.querySelectorAll('tbody tr');
      
      rows.forEach(row => {
        // Check data attributes - handle both string and boolean values
        const doneAttr = row.getAttribute('data-done');
        const favoritedAttr = row.getAttribute('data-favorited');
        
        const isDone = doneAttr === 'true' || doneAttr === true;
        const isFavorited = favoritedAttr === 'true' || favoritedAttr === true;
        
        let showRow = true;
        
        // If both filters are checked, show only rows that match both
        if (showDoneOnly && showFavoritedOnly) {
          showRow = isDone && isFavorited;
        }
        // If only done filter is checked
        else if (showDoneOnly && !showFavoritedOnly) {
          showRow = isDone;
        }
        // If only favorited filter is checked
        else if (!showDoneOnly && showFavoritedOnly) {
          showRow = isFavorited;
        }
        // If no filters are checked, show all rows
        else {
          showRow = true;
        }
        
        row.style.display = showRow ? '' : 'none';
      });
      
      // Update table visibility message
      updateResultsCount();
    }
    
    function updateResultsCount() {
      const allRows = table.querySelectorAll('tbody tr');
      let visibleCount = 0;
      allRows.forEach(row => {
        if (row.style.display !== 'none') {
          visibleCount++;
        }
      });
      const totalRows = allRows.length;
      
      // Remove existing count message
      const existingMessage = document.querySelector('.filter-results-count');
      if (existingMessage) {
        existingMessage.remove();
      }
      
      // Add new count message if filtering is active
      if (filterDone.checked || filterFavorited.checked) {
        const message = document.createElement('p');
        message.className = 'filter-results-count';
        message.textContent = `Showing ${visibleCount} of ${totalRows} segments`;
        table.parentNode.insertBefore(message, table);
      }
    }
    
    filterDone.addEventListener('change', applyFilters);
    filterFavorited.addEventListener('change', applyFilters);
    
    // Also add event listeners using onclick for better compatibility
    filterDone.onclick = applyFilters;
    filterFavorited.onclick = applyFilters;
  }
});

// Also try with window.onload as a fallback
window.addEventListener('load', function() {
  const filterDone = document.getElementById('filter-done');
  const filterFavorited = document.getElementById('filter-favorited');
  const table = document.getElementById('segments-table');
  
  if (filterDone && filterFavorited && table) {
    const applyFilters = function() {
      const showDoneOnly = filterDone.checked;
      const showFavoritedOnly = filterFavorited.checked;
      const rows = table.querySelectorAll('tbody tr');
      
      rows.forEach(row => {
        const isDone = row.getAttribute('data-done') === 'true';
        const isFavorited = row.getAttribute('data-favorited') === 'true';
        
        let showRow = true;
        
        if (showDoneOnly && !isDone) {
          showRow = false;
        }
        if (showFavoritedOnly && !isFavorited) {
          showRow = false;
        }
        
        row.style.display = showRow ? '' : 'none';
      });
    };
    
    filterDone.addEventListener('change', applyFilters);
    filterFavorited.addEventListener('change', applyFilters);
  }
});

// Clear all filters
window.clearFilters = function() {
  const filterDone = document.getElementById('filter-done');
  const filterFavorited = document.getElementById('filter-favorited');
  
  if (filterDone) filterDone.checked = false;
  if (filterFavorited) filterFavorited.checked = false;
  
  // Show all rows
  const table = document.getElementById('segments-table');
  if (table) {
    const rows = table.querySelectorAll('tbody tr');
    rows.forEach(row => {
      row.style.display = '';
    });
    
    // Remove count message
    const existingMessage = document.querySelector('.filter-results-count');
    if (existingMessage) {
      existingMessage.remove();
    }
  }
}

// Handle segment marking with pure fetch requests
window.markSegment = function(segmentId, markingType) {
  const button = event.target;
  const originalText = button.textContent;
  
  // Disable button and show loading state
  button.disabled = true;
  button.style.opacity = '0.6';
  
  // Get CSRF token for Rails
  const csrfToken = document.querySelector('meta[name="csrf-token"]');
  const token = csrfToken ? csrfToken.getAttribute('content') : '';
  
  // Determine the correct URL based on marking type
  let url;
  switch(markingType) {
    case 'done':
      url = `/segments/${segmentId}/mark_done`;
      break;
    case 'favorited':
      url = `/segments/${segmentId}/mark_favorited`;
      break;
    case 'unavailable':
      url = `/segments/${segmentId}/mark_unavailable`;
      break;
    default:
      console.error('Unknown marking type:', markingType);
      button.disabled = false;
      button.style.opacity = '1';
      return;
  }
  
  console.log(`Making request to: ${url}`);
  
  // Make fetch request
  fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-CSRF-Token': token,
      'X-Requested-With': 'XMLHttpRequest'
    },
    credentials: 'same-origin'
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      updateSegmentRow(segmentId, data.background_class, data.status);
      showNotification(`Segment marked as ${data.status}`, 'success');
    } else {
      showNotification(data.error || 'An error occurred', 'error');
    }
  })
  .catch(error => {
    console.error('Error:', error);
    showNotification('Network error occurred', 'error');
  })
  .finally(() => {
    // Re-enable button
    button.disabled = false;
    button.style.opacity = '1';
  });
};

function updateSegmentRow(segmentId, backgroundClass, status) {
  // Find the table row for this segment by checking the onclick attributes
  const rows = document.querySelectorAll('#segments-table tbody tr');
  
  rows.forEach(row => {
    const actionCell = row.querySelector('.segment-actions');
    if (!actionCell) return;
    
    // Check if this row contains buttons for the segment
    const segmentButtons = actionCell.querySelectorAll(`[onclick*="'${segmentId}'"]`);
    if (segmentButtons.length === 0) return;
    
    // Update row background class
    row.className = backgroundClass;
    
    // Update data attributes for client-side filtering
    row.setAttribute('data-done', status === 'done' ? 'true' : 'false');
    row.setAttribute('data-favorited', status === 'favorited' ? 'true' : 'false');
    row.setAttribute('data-unavailable', status === 'unavailable' ? 'true' : 'false');
    
    // Update button active states
    const doneBtn = actionCell.querySelector('.btn-done');
    const favoriteBtn = actionCell.querySelector('.btn-favorite');
    const unavailableBtn = actionCell.querySelector('.btn-unavailable');
    
    // Remove all active classes first
    [doneBtn, favoriteBtn, unavailableBtn].forEach(btn => {
      if (btn) btn.classList.remove('active');
    });
    
    // Add active class to the appropriate button
    if (status === 'done' && doneBtn) {
      doneBtn.classList.add('active');
    } else if (status === 'favorited' && favoriteBtn) {
      favoriteBtn.classList.add('active');
    } else if (status === 'unavailable' && unavailableBtn) {
      unavailableBtn.classList.add('active');
    }
  });
}

function showNotification(message, type) {
  // Create notification element
  const notification = document.createElement('div');
  notification.className = `flash-${type === 'success' ? 'notice' : 'alert'}`;
  notification.textContent = message;
  notification.style.position = 'fixed';
  notification.style.top = '20px';
  notification.style.right = '20px';
  notification.style.zIndex = '1000';
  notification.style.maxWidth = '300px';
  
  document.body.appendChild(notification);
  
  // Remove notification after 3 seconds
  setTimeout(() => {
    if (notification.parentNode) {
      notification.parentNode.removeChild(notification);
    }
  }, 3000);
}
