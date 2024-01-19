define("ace/theme/sunburst",["require","exports","module","ace/lib/dom"], function(require, exports, module) {/* ***** BEGIN LICENSE BLOCK *****
 * Distributed under the BSD license:
 *
 * Copyright (c) 2010, Ajax.org B.V.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Ajax.org B.V. nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL AJAX.ORG B.V. BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * ***** END LICENSE BLOCK ***** */


exports.isDark = true;
exports.cssClass = "ace-sunburst";
exports.cssText = ".ace-sunburst .ace_gutter {\
background: #000000;\
color: rgb(124,124,124)\
}\
.ace-sunburst .ace_print-margin {\
width: 1px;\
background: #e8e8e8\
}\
.ace-sunburst {\
background-color: #000000;\
color: #F8F8F8\
}\
.ace-sunburst .ace_cursor {\
color: #A7A7A7\
}\
.ace-sunburst .ace_marker-layer .ace_selection {\
background: rgba(221, 240, 255, 0.20)\
}\
.ace-sunburst.ace_multiselect .ace_selection.ace_start {\
box-shadow: 0 0 3px 0px #000000;\
border-radius: 2px\
}\
.ace-sunburst .ace_marker-layer .ace_step {\
background: rgb(198, 219, 174)\
}\
.ace-sunburst .ace_marker-layer .ace_bracket {\
margin: -1px 0 0 -1px;\
border: 1px solid rgba(202, 226, 251, 0.24)\
}\
.ace-sunburst .ace_marker-layer .ace_active-line {\
background: rgba(255, 255, 255, 0.10)\
}\
.ace-sunburst .ace_gutter-active-line {\
background-color: rgba(255, 255, 255, 0.10)\
}\
.ace-sunburst .ace_marker-layer .ace_selected-word {\
border: 1px solid rgba(221, 240, 255, 0.20)\
}\
.ace-sunburst .ace_fold {\
background-color: #E28964;\
border-color: #F8F8F8\
}\
.ace-sunburst .ace_keyword {\
color: #E28964\
}\
.ace-sunburst .ace_constant {\
color: #3387CC\
}\
.ace-sunburst .ace_support {\
color: #9B859D\
}\
.ace-sunburst .ace_support.ace_function {\
color: #DAD085\
}\
.ace-sunburst .ace_support.ace_constant {\
color: #CF6A4C\
}\
.ace-sunburst .ace_storage {\
color: #99CF50\
}\
.ace-sunburst .ace_invalid.ace_illegal {\
color: #FD5FF1;\
background-color: rgba(86, 45, 86, 0.75)\
}\
.ace-sunburst .ace_invalid.ace_deprecated {\
text-decoration: underline;\
font-style: italic;\
color: #FD5FF1\
}\
.ace-sunburst .ace_string {\
color: #65B042\
}\
.ace-sunburst .ace_string.ace_regexp {\
color: #E9C062\
}\
.ace-sunburst .ace_comment {\
font-style: italic;\
color: #AEAEAE\
}\
.ace-sunburst .ace_variable {\
color: #3E87E3\
}\
.ace-sunburst .ace_meta.ace_tag {\
color: #89BDFF\
}\
.ace-sunburst .ace_markup.ace_heading {\
color: #FEDCC5;\
background-color: #632D04\
}\
.ace-sunburst .ace_markup.ace_list {\
color: #E1D4B9\
}";

var dom = require("../lib/dom");
dom.importCssString(exports.cssText, exports.cssClass);

});                (function() {
                    window.require(["ace/theme/sunburst"], function(m) {
                        if (typeof module == "object" && typeof exports == "object" && module) {
                            module.exports = m;
                        }
                    });
                })();
            