if(localStorage && localStorage.getItem('viewType') == 'list')
  $('#filesDisplay').addClass('list-view')

function confirmFileRename(path) {
  $('#renamePathInput').val(path);
  $('#renameNewPathInput').val(path);
  $('#renameModal').modal();
}

function confirmFileDelete(name) {
  $('#deleteFileName').text(name);
  $('#deleteConfirmModal').modal();
}

function fileDelete() {
  $('#deleteFilenameInput').val($('#deleteFileName').html());
  $('#deleteFilenameForm').submit();
}

function clickUploadFiles() {
  $("input[id='uploadFiles']").click()
}

function showUploadProgress() {
  $('#uploadingOverlay').css('display', 'block')
}

function hideUploadProgress() {
  $('#progressBar').css('display', 'none')
  $('#uploadingOverlay').css('display', 'none')
}

$('#createDir').on('shown', function () {
  $('#newDirInput').focus();
})

$('#createFile').on('shown', function () {
  $('#newFileInput').focus();
  $('#newFileInput').val('');
  clearCreateFileError();
})

function showCreateFileError(message) {
  var errorDiv = $('#createFileError');
  errorDiv.text(message);
  errorDiv.show();
}

function clearCreateFileError() {
  var errorDiv = $('#createFileError');
  errorDiv.hide();
  errorDiv.text('');
}

function fileExists(filePath) {
  // Check if a file with this path already exists in the current file listing
  // Each file has a hidden div containing the file path
  var exists = false;
  var lowerFilePath = filePath.toLowerCase();
  
  $('#filesDisplay .file .overlay div[style*="display: none"]').each(function() {
    var existingPath = $(this).text().trim();
    if (existingPath.toLowerCase() === lowerFilePath) {
      exists = true;
      return false; // Break out of each loop
    }
  });
  
  return exists;
}

$('#newFileInput').on('keypress', function(e) {
  if (e.which === 13) { // Enter key
    handleCreateFile();
  }
})

function handleCreateFile() {
  var filename = $('#newFileInput').val();
  var dir = $('#createFileDir').val();
  var csrfToken = $('#createFileCSRFToken').val();
  
  // Don't hide modal yet - wait for success or error
  createFileViaAPI(filename, dir, csrfToken);
}

function listView() {
  if(localStorage)
    localStorage.setItem('viewType', 'list')

  $('#filesDisplay').addClass('list-view')
}

function iconView() {
  if(localStorage)
    localStorage.removeItem('viewType')

  $('#filesDisplay').removeClass('list-view')
}

function alertAdd(text) {
  var a = $('#alertDialogue');
  a.css('display', 'block');
  a.append(text+'<br>');
}

function alertClear(){
  var a = $('#alertDialogue');
  a.css('display', 'none');
  a.text('');
}

function alertType(type){
  var a = $('#alertDialogue');
  a.removeClass('alert-success');
  a.removeClass('alert-error');
  a.addClass('alert-'+type);
}

var processedFiles = 0;
var uploadedFiles = 0;
var uploadedFileErrors = 0;

function joinPaths(...paths) {
  return paths
    .map(path => path.replace(/(^\/|\/$)/g, ''))
    .filter(path => path !== '')
    .join('/');
}

function reInitDashboardFiles() {
  new Dropzone("#uploads", {
    url: "/api/upload",
    paramName: 'file',
    dictDefaultMessage: "",
    uploadMultiple: false,
    parallelUploads: 1,
    maxFilesize: 104857600, // 100MB
    clickable: document.getElementById('uploadButton'),
    init: function() {
      this.on("processing", function(file) {
        var dir = $('#uploads input[name="dir"]').val();
        if(file.fullPath) {
          this.options.paramName = joinPaths(dir,file.fullPath);
        } else {
          this.options.paramName = joinPaths(dir, file.name);
        }

        processedFiles++;
        $('#uploadFileName').text(this.options.paramName).prepend('<i class="icon-file"></i> ');
      });

      this.on("success", function(file) {
        uploadedFiles++;
      });

      this.on("error", function(file, message) {
        uploadedFiles++;
        uploadedFileErrors++;
        alertType('error');
        if (message && message.message) {
          alertAdd(message.message);
        } else {
          alertAdd(this.options.paramName+' failed to upload');
        }
      });

      this.on("queuecomplete", function() {
        hideUploadProgress();
        if(uploadedFileErrors > 0) {
          alertType('error');
          alertAdd(uploadedFiles-uploadedFileErrors+'/'+uploadedFiles+' files uploaded successfully');
        } else {
          alertType('success');
          alertAdd(uploadedFiles+' files uploaded successfully');
        }
        reloadDashboardFiles();
      });

      this.on("addedfiles", function(files) {
        uploadedFiles = 0;
        uploadedFileErrors = 0;
        alertClear();
        showUploadProgress();
      });
    }
  });

  document.getElementById('uploadButton').addEventListener('click', function(event) {
      event.preventDefault();
  });
}

function reloadDashboardFiles() {
  var dir = $('#uploads input[name="dir"]').val();
  $.get('/dashboard/files?dir='+encodeURIComponent(dir), function(data) {
    $('#filesDisplay').html(data);
    reInitDashboardFiles();
  });
}

function createFileViaAPI(filename, dir, csrfToken) {
  clearCreateFileError();
  showUploadProgress();
  
  filename = filename.replace(/[^a-zA-Z0-9_\-.]/g, '');
  
  if (!filename || filename.trim() === '') {
    hideUploadProgress();
    showCreateFileError('You must provide a file name.');
    return;
  }
  
  var extMatch = filename.match(/\.([^.]+)$/);

  // Check if extension is allowed for editing (if there is one)
  if (extMatch) {
    var extension = extMatch[1].toLowerCase();
    var validExtensions = [
      'html', 'htm', 'txt', 'js', 'css', 'scss', 'md', 'manifest', 'less', 
      'webmanifest', 'xml', 'json', 'opml', 'rdf', 'svg', 'gpg', 'pgp', 
      'resolvehandle', 'pls', 'yaml', 'yml', 'toml', 'osdx', 'mjs', 'cjs', 
      'ts', 'py', 'rss', 'glsl'
    ];
    
    if (validExtensions.indexOf(extension) === -1) {
      hideUploadProgress();
      showCreateFileError('Must be an editable file type (' + validExtensions.join(', ') + ') or a file with no extension.');
      return;
    }
  }
  // Files with no extension are allowed (they're treated as text files)
  
  var fullPath = dir ? joinPaths(dir, filename) : filename;
  
  // Check if file already exists
  if (fileExists(fullPath)) {
    hideUploadProgress();
    showCreateFileError('A file with this name already exists. Please choose a different name.');
    return;
  }
  
  var isHTML = /\.(html|htm)$/i.test(filename);
  
  // Create default HTML template content
  var htmlTemplate = '<!DOCTYPE html>\n' +
    '<html>\n' +
    '  <head>\n' +
    '    <meta charset="UTF-8">\n' +
    '    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n' +
    '    <title>My Page</title>\n' +
    '    <link href="/style.css" rel="stylesheet" type="text/css" media="all">\n' +
    '  </head>\n' +
    '  <body>\n' +
    '  </body>\n' +
    '</html>';
  
  var content = isHTML ? htmlTemplate : '';
  
  // Create a blob with the content
  var blob = new Blob([content], { type: 'text/plain' });
  
  // Create FormData for the API upload
  var formData = new FormData();
  formData.append('csrf_token', csrfToken);
  formData.append(fullPath, blob, filename);
  
  $.ajax({
    url: '/api/upload',
    type: 'POST',
    data: formData,
    processData: false,
    contentType: false,
    success: function(response) {
      hideUploadProgress();
      alertClear();
      alertType('success');
      var escapedName = $('<div>').text(fullPath).html(); // HTML escape
      alertAdd(escapedName + ' was created! <a style="color: #FFFFFF; text-decoration: underline" href="/site_files/text_editor/' + encodeURIComponent(fullPath) + '">Click here to edit it</a>.');
      reloadDashboardFiles();
      $('#createFile').modal('hide'); // Hide modal on success
    },
    error: function(xhr) {
      hideUploadProgress();
      try {
        var errorData = JSON.parse(xhr.responseText);
        showCreateFileError(errorData.message || 'Failed to create file');
      } catch(e) {
        showCreateFileError('Failed to create file');
      }
    }
  });
}

// for first time load
reInitDashboardFiles();
