document.addEventListener('DOMContentLoaded', () => {
  const chatForm = document.getElementById('chat-form');
  const chatBox = document.getElementById('chat-box');
  const chatInput = document.getElementById('chat-input');
  let messages = [];
  let accumulatingMessage = '';
  let system = `
  You are Daria from the TV show Daria, and you still have her personality and you should answer all questions with her general attitude. You are a coding assistant created to help users develop static websites on Neocities using HTML, CSS, and JavaScript. Provide clear, concise explanations and efficient solutions, focusing on clean, readable, and well-commented code. Break down complex concepts and offer guidance on best practices for accessibility, responsiveness, and performance optimization.

  The user's website consists of:
  - index.html (main page)
  - not_found.html (404 page)
  - style.css (site styles)
  - Additional uploaded files and directories

  HTML files lose their extension when loaded in the browser (e.g., /about.html becomes /about). The user edits files using a text-based HTML editor.

  When responding to queries:
  1. Greet the user and acknowledge their question.
  2. Provide a clear, detailed explanation.
  3. Provide all responses in markdown, including code snippits (e.g., \`\`\`html for HTML, \`\`\`css for CSS, \`\`\`js for JavaScript).
  4. Use 2-space soft tabs and include unicode support + viewport meta tag in HTML examples.
  5. Only use images from the user's Neocities site.
  6. Offer additional tips, best practices, or creative ideas.
  7. For factual info, only use information attributable to Wikipedia.
  8. Focus on coding questions and solutions.
  9. Encourage further questions and express enthusiasm for helping create an amazing website.
  10. When designing a web site, be creative, colorful, never use black or white. You want to impress people with your creative web design.

  Maintain a friendly, patient, supportive tone. Prioritize the user's learning and success in creating unique, engaging, functional static websites on Neocities.
  `;

  chatForm.addEventListener('submit', function(event) {

      event.preventDefault();
      const message = chatInput.value.trim();

      if (!message) {
        return;
      }
      
      chatForm.querySelector('button').disabled = true;

      addMessage('user');
      messages.push({role: 'user', content: message})
      chatBox.lastElementChild.innerHTML = DOMPurify.sanitize(message);

      const highlightedCode = hljs.highlight(message, { language: 'plaintext' }).value
      chatBox.lastElementChild.innerHTML = DOMPurify.sanitize(highlightedCode);
      chatBox.lastElementChild.querySelectorAll('a').forEach((link) => {
        link.setAttribute('target', '_blank');
      });

      chatInput.value = '';

      var formData = new FormData();
      formData.append('csrf_token', chatForm.querySelector('input[name="csrf_token"]').value);
      let systemWithFile = system + "\nThis is the user's current file they are editing:\n" + editor.getValue();
      formData.append('system', systemWithFile);
      formData.append('messages', JSON.stringify(messages));

      var source = new SSE('/site_files/chat', {payload: formData, debug: false});

      source.addEventListener('message_start', function(e) {
        var payload = JSON.parse(e.data);
        addMessage('bot', '')
      });

      source.addEventListener('content_block_start', function(e) {
        var payload = JSON.parse(e.data);
      });

      source.addEventListener('content_block_delta', function(e) {
        var payload = JSON.parse(e.data);
        accumulatingMessage += payload.delta.text;
        const messageElement = chatBox.lastElementChild;
        messageElement.innerHTML = DOMPurify.sanitize(marked.parse(accumulatingMessage));
        messageElement.querySelectorAll('code').forEach((block) => {
          hljs.highlightElement(block);
          addCopyButton(messageElement)
        });
        
        messageElement.querySelectorAll('a').forEach((link) => {
          link.setAttribute('target', '_blank');
        });

        scrollToBottom();
      });

      source.addEventListener('content_block_stop', function(e) {
        var payload = JSON.parse(e.data);
        messages.push({role: 'assistant', content: accumulatingMessage})
        accumulatingMessage = '';
        chatForm.querySelector('button').disabled = false;
      });
  });

  function addMessage(sender) {
      const messageElement = document.createElement('div');
      messageElement.classList.add('message', `${sender}-message`);
      chatBox.appendChild(messageElement);
      scrollToBottom();
  }


  // Keeps the chat box scrolled to the bottom

  // Function to scroll to the bottom
  function scrollToBottom() {
    // Check if auto-scrolling is enabled
    if (shouldAutoScroll) {
      chatBox.scrollTop = chatBox.scrollHeight;
    }
  }

  // Flag to keep track of whether auto-scrolling should be performed
  let shouldAutoScroll = true;

  window.onload = function() {
    scrollToBottom();
    // Detect manual scrolling by the user
    chatBox.addEventListener('scroll', () => {
      // Calculate the distance from the bottom
      const distanceFromBottom = chatBox.scrollHeight - chatBox.scrollTop - chatBox.clientHeight;

      // If the distance from the bottom is small (or zero), the user is at the bottom
      if (distanceFromBottom < 1) {
        shouldAutoScroll = true;
      } else {
        // If the user has scrolled up, disable auto-scrolling
        shouldAutoScroll = false;
      }
    });
  };

  const observer = new MutationObserver(scrollToBottom);
  observer.observe(chatBox, { childList: true });


  // Copy button

  function addCopyButton(parentElement) {
    const codeBoxes = parentElement.querySelectorAll('pre code');

    codeBoxes.forEach(codeBox => {
      const copyButton = document.createElement('button');
      copyButton.innerText = 'Copy';
      copyButton.classList.add('copy-button');

      copyButton.addEventListener('click', () => {
        const code = codeBox.innerText;
        navigator.clipboard.writeText(code);
        copyButton.innerText = 'Copied!';
        setTimeout(() => {
          copyButton.innerText = 'Copy';
        }, 2000);
      });

      codeBox.parentElement.style.position = 'relative';
      codeBox.parentElement.appendChild(copyButton);
    });
  }



  // Resize chat box
  const handle = document.querySelector('.resize-handle');
  const leftCol = document.querySelector('.left-col');
  const rightCol = document.querySelector('.right-col');
  const editorRow = document.querySelector('.row.editor');
  let isResizing = false;

  handle.addEventListener('mousedown', function(e) {
    e.preventDefault();
    isResizing = true;
    let startX = e.pageX;

    function handleMouseMove(e) {
      if (!isResizing) return;
      const editorRowWidth = editorRow.offsetWidth; // Get the total width of the editor row
      let moveX = e.pageX - startX;
      let leftColWidth = leftCol.offsetWidth + moveX;

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
      startX = e.pageX;
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