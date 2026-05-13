document.addEventListener('DOMContentLoaded', () => {
    
  const handle = document.querySelector('.resize-handle');
  const leftCol = document.querySelector('.left-col');
  const rightCol = document.querySelector('.right-col');
  const editorRow = document.querySelector('.row.editor');
  let isResizing = false;

  if(!localStorage.getItem('leftColPct')) localStorage.setItem('leftColPct', '70%')
  if(!localStorage.getItem('rightColPct')) localStorage.setItem('rightColPct', '30%')
  handle.addEventListener('mousedown', function(e) {
    e.preventDefault();
    isResizing = true;
    let startX = e.pageX;
    let initialLeftColWidth = leftCol.offsetWidth; // Capture the initial width when resizing starts
  
    function handleMouseMove(e) {
      if (!isResizing) return;
      const editorRowWidth = editorRow.offsetWidth; // Get the total width of the editor row
      let moveX = e.pageX - startX;
      let leftColWidth = initialLeftColWidth + moveX; // Use the initial width for relative adjustments
  
      // Convert to percentage
      let leftColPercentage = (leftColWidth / editorRowWidth) * 100;
      let rightColPercentage = 100 - leftColPercentage;
  
      // Check and enforce the minimum and maximum widths
      if (rightColPercentage < 20) { // Minimum 20% for right column
        rightColPercentage = 20;
        leftColPercentage = 80;
      } else if (rightColPercentage > 80) { // Maximum 80% for right column
        rightColPercentage = 80;
        leftColPercentage = 20;
      }
  
      // Apply the new widths
      leftCol.style.width = `${leftColPercentage}%`;
      rightCol.style.width = `${rightColPercentage}%`;
      localStorage.setItem('leftColPct', `${leftColPercentage}%`);
      localStorage.setItem('rightColPct', `${rightColPercentage}%`);
    }
  
    function handleMouseUp() {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
      isResizing = false;
    }
  
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
  });
});

function togglePreview() {
  const leftCol = document.querySelector('.left-col');
  var preview = document.getElementById('preview');
  
  if (preview.style.display === 'none' || preview.style.display === '') {
    preview.style.display = 'block';
  } else {
    preview.style.display = 'none';
    leftCol.style.width = `100%`;
  }
}

