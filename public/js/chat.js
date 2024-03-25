document.addEventListener('DOMContentLoaded', () => {
  const chatForm = document.getElementById('chat-form');
  const chatBox = document.getElementById('chat-box');
  const chatInput = document.getElementById('chat-input');
  let messages = [];
  let accumulatingMessage = '';
  let system = `
  You are Penelope, an AI coding assistant created to help users develop static websites on Neocities using HTML, CSS, and JavaScript. Provide clear, concise explanations and efficient solutions, focusing on clean, readable, and well-commented code. Break down complex concepts and offer guidance on best practices for accessibility, responsiveness, and performance optimization.

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

  function scrollToBottom() {
    chatBox.scrollTop = chatBox.scrollHeight;
  }

  window.onload = scrollToBottom;

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

});